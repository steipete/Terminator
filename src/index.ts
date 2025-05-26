#!/usr/bin/env node
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
    getEnvVarBool,
    CURRENT_TERMINAL_APP,
    SERVER_VERSION
} from './config.js';
import { SWIFT_CLI_PATH } from './swift-cli.js';
import { terminatorTool } from './tool.js'; // Assuming terminatorTool.handler is adaptable
import { TerminatorExecuteParams, SdkCallContext } from './types.js';
import { logger, flushLogger } from './logger.js';

async function main() {
    // Startup checks for Swift CLI binary
    if (!fs.existsSync(SWIFT_CLI_PATH)) {
        logger.fatal(`Swift CLI binary not found at expected path: ${SWIFT_CLI_PATH}`);
        await flushLogger();
        process.exit(1);
    }
    try {
        fs.accessSync(SWIFT_CLI_PATH, fs.constants.X_OK);
    } catch (err) {
        logger.fatal(`Swift CLI binary at ${SWIFT_CLI_PATH} is not executable. Please run 'chmod +x ${SWIFT_CLI_PATH}'.`);
        await flushLogger();
        process.exit(1);
    }

    if (!process.env.MCP_PORT && !process.env.MCP_SERVER_VIA_STDIO) { // StdioServerTransport doesn't use MCP_PORT
        logger.warn('MCP_PORT or MCP_SERVER_VIA_STDIO environment variable is not set. This plugin is meant to be run by an MCP host over stdio.');
        // return; // Allow to run for local testing if needed
    }

    const server = new McpServer(
        {
            name: 'terminator-mcp', // Toolset name
            version: SERVER_VERSION,
        },
        {
            capabilities: {
                tools: {}, // Corrected: an empty object to indicate tool support
            },
        }
    );

    // ListTools handler
    server.setRequestHandler(ListToolsRequestSchema, async (): Promise<{ tools: Tool[] }> => {
        // Adapt our terminatorTool to the Tool type expected by the SDK
        const dynamicDescription = `${terminatorTool.description} \nTerminator MCP ${SERVER_VERSION} using ${CURRENT_TERMINAL_APP}`;
        const toolDefinition: Tool = {
            name: terminatorTool.name,
            description: dynamicDescription, // Use the dynamically suffixed description
            inputSchema: terminatorTool.inputSchema as any, 
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

        const receivedArgs = request.params.arguments;
        debugLog(`[MainServer] CallTool '${toolName}' receivedArgs (flattened):`, receivedArgs);
        
        if (!receivedArgs) { // Basic check for arguments
            throw new McpError(ErrorCode.InvalidParams, `Missing arguments for tool ${toolName}`);
        }

        // Validate that receivedArgs contains an 'action' (still required)
        if (typeof (receivedArgs as any).action !== 'string') {
            debugLog(`[MainServer] CallTool '${toolName}' failed validation: typeof action = ${typeof (receivedArgs as any)?.action}`);
            throw new McpError(ErrorCode.InvalidParams, `Missing or invalid 'action' (string expected) in arguments for tool ${toolName}`);
        }

        // Validate that receivedArgs contains a 'project_path' (now mandatory)
        if (typeof (receivedArgs as any).project_path !== 'string' || !(receivedArgs as any).project_path.trim()) {
            debugLog(`[MainServer] CallTool '${toolName}' failed validation: typeof project_path = ${typeof (receivedArgs as any)?.project_path}, value = ${(receivedArgs as any)?.project_path}`);
            throw new McpError(ErrorCode.InvalidParams, `Missing or invalid 'project_path' (non-empty string expected) in arguments for tool ${toolName}`);
        }

        // Cast receivedArgs directly to TerminatorExecuteParams as it's now flat
        const toolParams = receivedArgs as unknown as TerminatorExecuteParams;

        try {
            const result = await terminatorTool.handler(toolParams, { abortSignal: call.signal } as SdkCallContext); 
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
        logger.error({ error }, 'TerminatorMCP Server Error');
        // Optionally, send a diagnostic error to the client if possible/appropriate
    };
    process.on('SIGINT', async () => {
        logger.info('Received SIGINT, shutting down gracefully');
        await server.close();
        await flushLogger();
        process.exit(0);
    });
    
    try {
        const transport = new StdioServerTransport();
        await server.connect(transport);
        logger.info(`Terminator MCP server v${SERVER_VERSION} running via stdio, connected to host.`);
    } catch (error) {
        logger.error({ error }, 'Failed to start or connect Terminator MCP server');
        await flushLogger();
        process.exit(1);
    }
}

main().catch(async err => {
    logger.fatal({ error: err }, "Terminator MCP plugin failed to run (uncaught error in main)");
    await flushLogger();
    process.exit(1);
});

debugLog('Terminator MCP Plugin (Node.js Wrapper) Initializing for ESM...');
// Initial debug logs from config.ts will cover specific config values. 