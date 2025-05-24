// Placeholder for the main entry point of the @steipete/terminator-mcp package.
// This file will implement the MCP server logic and interface with the Swift CLI.

import { McpServer } from 'modelcontextprotocol';
// import * as path from 'path'; // No longer needed here if SWIFT_CLI_PATH is in swift-cli.ts
import * as fs from 'fs'; 
// import { TerminatorOptions, TerminatorExecuteParams, TerminatorResult } from './types'; // No longer needed directly
import {
    debugLog,
    getEnvVarBool 
} from './config';
import { SWIFT_CLI_PATH } from './swift-cli'; 
// import {
//     resolveEffectiveProjectPath,
//     resolveDefaultTag,
//     formatCliOutputForAI
// } from './utils'; // No longer needed directly
import { terminatorTool } from './tool'; // Import the tool

// terminatorTool definition removed

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

    if (!process.env.MCP_PORT) {
        console.warn('MCP_PORT environment variable is not set. This plugin is meant to be run by an MCP host.');
        // Optionally, add a simple direct test call here if needed for local debugging without MCP host
        // Example: 
        // const testContext: any = { signal: new AbortController().signal, requestContext: { roots: [] } };
        // terminatorTool.handler({ action: 'info', options: {} }, testContext)
        //   .then(res => console.log("Local test (info):", res))
        //   .catch(err => console.error("Local test (info) failed:", err));
        return;
    }

    const server = new McpServer({
        port: parseInt(process.env.MCP_PORT, 10),
        tools: [terminatorTool],
        verbose: getEnvVarBool('MCP_VERBOSE', true), 
    });

    try {
        await server.start();
        console.log(`Terminator MCP server started on port ${process.env.MCP_PORT}`);
    } catch (error) {
        console.error('Failed to start Terminator MCP server:', error);
        process.exit(1);
    }
}

main().catch(err => {
    console.error("Terminator MCP plugin failed to run (uncaught error in main):", err);
    process.exit(1);
});

debugLog('Terminator MCP Plugin (Node.js Wrapper) Initializing...');
// Initial debug logs from config.ts will cover specific config values. 