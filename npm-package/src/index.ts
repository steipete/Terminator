// Placeholder for the main entry point of the @steipete/terminator-mcp package.
// This file will implement the MCP server logic and interface with the Swift CLI.

import { Server as McpServer } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
    McpError,
    ErrorCode,
    type ServerResult,
    type Tool,
} from '@modelcontextprotocol/sdk/types.js';
import * as fs from 'node:fs';
import {
    debugLog,
    getEnvVarBool
} from './config.js';
import { SWIFT_CLI_PATH } from './swift-cli.js';
import { terminatorTool } from './tool.js'; // Assuming terminatorTool.handler is adaptable
import { TerminatorExecuteParams } from './types.js';

// Read package version (optional, but good practice)
// import { createRequire } from 'node:module';
// const require = createRequire(import.meta.url);
// const packageJson = require('../package.json');
// const SERVER_VERSION = packageJson.version || '0.1.0';
const SERVER_VERSION = '0.1.0'; // Hardcode for now to avoid json import complexities

async function main() {
    // Startup checks for Swift CLI binary
    if (!fs.existsSync(SWIFT_CLI_PATH)) {
        console.error(`FATAL: Swift CLI binary not found at expected path: ${SWIFT_CLI_PATH}`);
        process.exit(1);
    }
    try {
        fs.accessSync(SWIFT_CLI_PATH, fs.constants.X_OK);
    } catch (err) {
        console.error(`FATAL: Swift CLI binary at ${SWIFT_CLI_PATH} is not executable. Please run 'chmod +x ${SWIFT_CLI_PATH}'.`);
        process.exit(1);
    }

    if (!process.env.MCP_PORT && !process.env.MCP_SERVER_VIA_STDIO) { // StdioServerTransport doesn't use MCP_PORT
        console.warn('MCP_PORT or MCP_SERVER_VIA_STDIO environment variable is not set. This plugin is meant to be run by an MCP host over stdio.');
        // return; // Allow to run for local testing if needed
    }

    const server = new McpServer(
        {
            name: 'terminator-mcp', // Toolset name
            version: SERVER_VERSION,
        },
        {
            capabilities: {
                // We define tools dynamically via ListToolsRequest
            },
        }
    );

    // ListTools handler
    server.setRequestHandler(ListToolsRequestSchema, async (): Promise<{ tools: Tool[] }> => {
        // Adapt our terminatorTool to the Tool type expected by the SDK
        const toolDefinition: Tool = {
            name: terminatorTool.name,
            description: terminatorTool.description,
            inputSchema: terminatorTool.inputSchema as any, // Cast if schema format differs slightly
            // outputSchema: terminatorTool.outputSchema as any, // outputSchema not part of SDK Tool type
        };
        return {
            tools: [toolDefinition],
        };
    });

    // CallTool handler
    server.setRequestHandler(CallToolRequestSchema, async (request, call): Promise<ServerResult> => {
        debugLog('[MainServer] Handling CallToolRequest:', request);

        const toolName = request.params.name;
        if (toolName !== terminatorTool.name) {
            throw new McpError(ErrorCode.MethodNotFound, `Tool ${toolName} not found. Available: ${terminatorTool.name}`);
        }

        const toolArguments = request.params.arguments as TerminatorExecuteParams['options']; // Cast directly for now

        try {
            // Pass `call` as the context, which contains `call.signal` for cancellation
            const result = await terminatorTool.handler({ action: request.params.action as any, options: toolArguments }, call);
            return { content: [{ type: 'text', text: result.message }] }; // Adapt result to ServerResult
        } catch (error: any) {
            debugLog('[MainServer] Error executing tool:', error);
            if (error instanceof McpError) {
                throw error;
            }
            throw new McpError(ErrorCode.InternalError, `Terminator tool execution failed: ${error.message}`);
        }
    });


    server.onerror = (error) => {
        console.error('[TerminatorMCP Server Error]', error);
        // Optionally, send a diagnostic error to the client if possible/appropriate
    };
    process.on('SIGINT', async () => {
        await server.close();
        process.exit(0);
    });
    
    try {
        const transport = new StdioServerTransport();
        await server.connect(transport);
        console.error(`Terminator MCP server v${SERVER_VERSION} running via stdio, connected to host.`);
    } catch (error) {
        console.error('Failed to start or connect Terminator MCP server:', error);
        process.exit(1);
    }
}

main().catch(err => {
    console.error("Terminator MCP plugin failed to run (uncaught error in main):", err);
    process.exit(1);
});

debugLog('Terminator MCP Plugin (Node.js Wrapper) Initializing for ESM...');
// Initial debug logs from config.ts will cover specific config values. 