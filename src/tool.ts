// Defines the main MCP tool, 'terminator.execute', including its schema,
// description, and the central handler function that orchestrates calls to other modules.
import { TerminatorOptions, TerminatorExecuteParams, TerminatorResult, SdkCallContext } from './types.js'; 
import {
    CURRENT_TERMINAL_APP, 
    DEFAULT_BACKGROUND_STARTUP_SECONDS, 
    DEFAULT_FOREGROUND_COMPLETION_SECONDS, 
    DEFAULT_LINES, 
    DEFAULT_FOCUS_ON_ACTION,
    DEFAULT_BACKGROUND_EXECUTION, 
    getCanonicalOptions,
    debugLog
} from './config.js';
import { invokeSwiftCLI, SwiftCLIResult, SWIFT_CLI_PATH } from './swift-cli.js';
import * as fs from 'node:fs'; 
import {
    resolveEffectiveProjectPath,
    resolveDefaultTag,
    formatCliOutputForAI
} from './utils.js';
import { logger, getLoggerConfig } from './logger.js';
import { validateExecuteParams, validateEnvironmentVariables } from './validation.js';
import { SERVER_VERSION } from './config.js';

export const terminatorTool = {
    name: 'execute',
    description: `Manages macOS terminal sessions using the ${CURRENT_TERMINAL_APP} application. Ideal for running commands that might be long-running or could hang, as it isolates them to protect your workflow and allows for faster interaction. The session screen is automatically cleared before executing a new command or after a process is killed. Use this to execute shell commands, retrieve output, and manage terminal processes.`,
    inputSchema: {
        type: 'object',
        properties: {
            action: {
                type: 'string',
                description: "Optional. The operation to perform: 'execute', 'read', 'list', 'info', 'focus', or 'kill'. Defaults to 'execute'.",
                enum: ['execute', 'read', 'list', 'info', 'focus', 'kill'],
                default: 'execute'
            },
            project_path: { type: 'string', description: 'Absolute path to the project directory. This is a mandatory field.' },
            tag: {
                type: 'string',
                description: 'Optional. A unique identifier for the session (e.g., "ui-build", "api-server"). If omitted, a tag will be derived from the project_path.',
                optional: true
            },
            command: {
                type: 'string',
                description: "Optional, primarily for action: 'execute'. The shell command to execute. If action is 'execute' and command is empty or omitted, the session will be prepared (cleared, focused if applicable), but no new command is run.",
                optional: true
            },
            background: {
                type: 'boolean',
                description: 'If true, command is long-running (default: false).',
                optional: true,
                default: false
            },
            lines: {
                type: 'number',
                description: 'Max recent output lines (default: 100).',
                optional: true,
                default: 100
            },
            timeout: {
                type: 'number',
                description: 'Timeout in seconds. Defaults depend on background flag (FG: 60s, BG: 5s).',
                optional: true
            },
            focus: {
                type: 'boolean',
                description: 'Bring terminal to front (default: true).',
                optional: true,
                default: true
            },
        },
        required: ['project_path'],
        additionalProperties: true,
    },
    outputSchema: {
        type: 'object',
        properties: {
            success: { type: 'boolean' },
            message: { type: 'string' },
        },
        required: ['success', 'message'],
    },
    async handler(params: TerminatorExecuteParams, context: SdkCallContext): Promise<TerminatorResult> {
        debugLog(`Received raw params:`, params);
        
        // Validate parameters
        const validation = validateExecuteParams(params);
        if (!validation.valid) {
            return { 
                success: false, 
                message: `Parameter validation failed:\n${validation.errors.join('\n')}` 
            };
        }

        const action = params.action || 'execute';
        
        // Map 'execute' to 'exec' for internal use
        const internalAction = action === 'execute' ? 'exec' : action;
        
        if (!['exec', 'execute', 'read', 'list', 'info', 'focus', 'kill'].includes(action)) {
            return { success: false, message: `Error: Invalid action '${action}'. Must be one of execute, read, list, info, focus, kill.` };
        }
        
        const options = getCanonicalOptions(params as any);

        debugLog(`Canonical options after processing:`, options);

        const effectiveProjectPath = resolveEffectiveProjectPath(params.project_path, undefined);
        if (!effectiveProjectPath) {
            return { success: false, message: `Error: project_path '${params.project_path}' could not be resolved or is invalid.` };
        }

        let commandOpt: string | undefined = typeof options.command === 'string' ? options.command : undefined;
        if (internalAction === 'exec' && options.command === undefined) commandOpt = '';
        
        let lines = typeof options.lines === 'number' ? options.lines : DEFAULT_LINES;
        if (typeof options.lines === 'string') lines = parseInt(options.lines, 10) || DEFAULT_LINES;

        let backgroundVal = options.background;
        let background = DEFAULT_BACKGROUND_EXECUTION; // Default value
        if (typeof backgroundVal === 'boolean') {
            background = backgroundVal;
        } else if (typeof backgroundVal === 'string') {
            background = ['true', '1', 't', 'yes', 'on'].includes(backgroundVal.toLowerCase());
        }

        let focusVal = options.focus;
        let focus = DEFAULT_FOCUS_ON_ACTION; // Default value
        if (typeof focusVal === 'boolean') {
            focus = focusVal;
        } else if (typeof focusVal === 'string') {
            focus = ['true', '1', 't', 'yes', 'on'].includes(focusVal.toLowerCase());
        }

        let timeoutOverride = typeof options.timeout === 'number' ? options.timeout : undefined;
        if (typeof options.timeout === 'string') timeoutOverride = parseInt(options.timeout, 10) || undefined;

        let tag = resolveDefaultTag(options.tag, effectiveProjectPath);

        if (!tag && ['exec', 'execute', 'read', 'kill', 'focus'].includes(action) && action !== 'list' && action !== 'info') {
            const errorMsg = 'Error: Could not determine a session tag even with a project_path. This indicates an internal issue.';
            logger.error({ tagVal: options.tag, projPath: effectiveProjectPath }, errorMsg);
            return { success: false, message: errorMsg };
        }
        
        const cliArgs: string[] = [internalAction];
        if (tag) {
            if (internalAction === 'list' && options.tag) { 
                /* Will be added as --tag option later */
            } else if (internalAction !== 'list' && internalAction !== 'info') {
                cliArgs.push(tag);
            }
        }

        if (effectiveProjectPath && internalAction !== 'info') {
            cliArgs.push('--project-path', effectiveProjectPath);
        }
        if (commandOpt !== undefined && internalAction === 'exec') { 
            // Only add --command if there's actually a command to execute
            // Empty string means "prepare session only" and shouldn't have --command flag
            if (commandOpt !== '') {
                cliArgs.push('--command', commandOpt);
            }
        }
        
        if (internalAction === 'exec' || internalAction === 'read') {
            cliArgs.push('--lines', lines.toString());
        }
        
        const focusModeCli = focus ? 'force-focus' : 'no-focus'; 
        if (['exec', 'read', 'kill', 'focus'].includes(internalAction)) {
            cliArgs.push('--focus-mode', focusModeCli);
        }

        if (internalAction === 'exec') {
            if (background) {
                cliArgs.push('--background');
            }
            if (timeoutOverride !== undefined) {
                 cliArgs.push('--timeout', timeoutOverride.toString());
            }
        }
        
        if (internalAction === 'list' || internalAction === 'info' || internalAction === 'read') {
            cliArgs.push('--json');
        }
        if (internalAction === 'list' && tag && options.tag) { 
            cliArgs.push('--tag', tag); 
        }

        const terminatorEnv: Record<string, string> = {};
        for (const key in process.env) {
            if (key.startsWith('TERMINATOR_')) {
                terminatorEnv[key] = process.env[key]!;
            }
        }
        
        const internalWrapperTimeout = Math.max(DEFAULT_FOREGROUND_COMPLETION_SECONDS * 1000, DEFAULT_BACKGROUND_STARTUP_SECONDS * 1000) + 60000;

        try {
            const result: SwiftCLIResult = await invokeSwiftCLI(cliArgs, terminatorEnv, context, internalWrapperTimeout);
            
            // Handle info action specially to add logger configuration
            if (internalAction === 'info' && result.exitCode === 0) {
                try {
                    const infoData = JSON.parse(result.stdout);
                    const loggerConfig = getLoggerConfig();
                    
                    // Add logger configuration to the info output
                    const envIssues = validateEnvironmentVariables();
                    infoData.logger = {
                        logFile: loggerConfig.logFile,
                        logLevel: loggerConfig.logLevel,
                        consoleLogging: loggerConfig.consoleLogging,
                        environmentVariables: {
                            TERMINATOR_LOG_FILE: process.env.TERMINATOR_LOG_FILE || '(not set)',
                            TERMINATOR_LOG_LEVEL: process.env.TERMINATOR_LOG_LEVEL || '(not set)',
                            TERMINATOR_CONSOLE_LOGGING: process.env.TERMINATOR_CONSOLE_LOGGING || '(not set)'
                        },
                        configurationIssues: envIssues
                    };
                    
                    // Verify Swift CLI binary
                    infoData.swiftCLI = {
                        path: SWIFT_CLI_PATH,
                        exists: fs.existsSync(SWIFT_CLI_PATH),
                        executable: (() => {
                            try {
                                fs.accessSync(SWIFT_CLI_PATH, fs.constants.X_OK);
                                return true;
                            } catch {
                                return false;
                            }
                        })()
                    };
                    
                    return { success: true, message: JSON.stringify(infoData, null, 2) };
                } catch (e) {
                    logger.error({ error: e }, 'Failed to parse info output');
                }
            }

            if (result.cancelled) {
                return { success: false, message: 'Terminator action cancelled by request.' };
            }
            if (result.internalTimeoutHit) {
                return { success: false, message: 'Terminator Swift CLI unresponsive and was terminated by the wrapper.' };
            }

            if (result.exitCode === null) {
                // Process crashed or was killed without proper exit
                let errMsg = result.stderr.trim() || result.stdout.trim() || '';
                
                // Build a comprehensive error message
                let errorDetails: string[] = [];
                
                // Check for common issues
                if (errMsg.includes('Permission denied') || errMsg.includes('not authorized')) {
                    errorDetails.push('Missing automation permissions. Grant Terminal/iTerm control in System Settings → Privacy & Security → Automation');
                } else if (errMsg.includes('command not found') || errMsg.includes('No such file')) {
                    errorDetails.push('Swift CLI binary may be missing or corrupt. Try reinstalling the package');
                } else if (errMsg.includes('Segmentation fault') || errMsg.includes('Illegal instruction')) {
                    errorDetails.push('Swift CLI crashed. This may be due to architecture mismatch or corrupted binary');
                } else if (errMsg === '') {
                    errorDetails.push('Swift CLI terminated without output. Possible causes:');
                    errorDetails.push('• Missing automation permissions (most common)');
                    errorDetails.push('• First run permission prompt waiting for response');
                    errorDetails.push('• Binary corruption or architecture mismatch');
                    errorDetails.push('• Terminal app not installed or not running');
                }
                
                // Add diagnostic info
                errorDetails.push(`Terminal app: ${CURRENT_TERMINAL_APP}`);
                errorDetails.push(`Action: ${internalAction}, Tag: ${tag || 'auto-generated'}`);
                if (commandOpt) errorDetails.push(`Command: ${commandOpt}`);
                errorDetails.push(`Project: ${effectiveProjectPath}`);
                
                // Add troubleshooting steps
                errorDetails.push('\nTroubleshooting:');
                errorDetails.push('1. Check System Settings → Privacy & Security → Automation');
                errorDetails.push('2. Try: tccutil reset AppleEvents com.apple.Terminal');
                errorDetails.push('3. Check logs: ~/Library/Logs/terminator-mcp/');
                
                const fullError = errorDetails.join('\n');
                return { success: false, message: `Terminator Error: Swift CLI process terminated unexpectedly\n\n${fullError}` };
            } else if (result.exitCode === 0) {
                const message = formatCliOutputForAI(internalAction, result, commandOpt, tag || undefined, background, timeoutOverride);
                return { success: true, message };
            } else {
                let errMsg = result.stderr.trim() || result.stdout.trim() || 'Unknown error from Swift CLI';
                
                // Handle specific exit codes
                if (result.exitCode === 2) {
                    errMsg = `Configuration Error: ${errMsg}`;
                } else if (result.exitCode === 3) {
                    errMsg = `AppleScript Communication Error: ${errMsg}`;
                } else if (result.exitCode === 4) {
                    errMsg = `Process Control Error: ${errMsg}`;
                } else if (result.exitCode === 5) {
                    errMsg = `Invalid CLI Arguments/Usage: ${errMsg}`;
                } else if (result.exitCode === 6) {
                    errMsg = `Unsupported Operation for App: ${errMsg}`;
                } else if (result.exitCode === 7) {
                    errMsg = `File/IO Error: ${errMsg}`;
                } else if (result.exitCode === 64) {
                    // Standard Unix exit code for command line usage error
                    errMsg = `Invalid Command Line Usage: ${errMsg}`;
                    
                    // Extract usage information if present
                    const usageMatch = errMsg.match(/Usage: (.+?)(?:\n|$)/);
                    if (usageMatch) {
                        errMsg += `\n\nCorrect usage: ${usageMatch[1]}`;
                    }
                }
                
                return { success: false, message: `Terminator Error (Swift CLI Code ${result.exitCode}): ${errMsg}` };
            }
        } catch (error: any) {
            logger.error({ error }, 'Error invoking or processing Swift CLI result');
            return { success: false, message: `Terminator plugin internal error: ${error.message}` };
        }
    }
}; 