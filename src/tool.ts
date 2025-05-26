// Defines the main MCP tool, 'terminator.execute', including its schema,
// description, and the central handler function that orchestrates calls to other modules.
// import { McpTool, McpContext } from '@modelcontextprotocol/sdk/types.js';
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
import { invokeSwiftCLI, SwiftCLIResult } from './swift-cli.js'; 
import {
    resolveEffectiveProjectPath,
    resolveDefaultTag,
    formatCliOutputForAI
} from './utils.js';

export const terminatorTool /*: McpTool<TerminatorExecuteParams, TerminatorResult>*/ = {
    name: 'execute',
    description: `Manages macOS terminal sessions using the ${CURRENT_TERMINAL_APP} application. Ideal for running commands that might be long-running or could hang, as it isolates them to protect your workflow and allows for faster interaction. The session screen is automatically cleared before executing a new command or after a process is killed. Use this to execute shell commands, retrieve output, and manage terminal processes.`,
    inputSchema: {
        type: 'object',
        properties: {
            action: { type: 'string', enum: ['exec', 'read', 'list', 'info', 'focus', 'kill'], description: "Optional. The operation to perform: 'execute', 'read', 'list', 'info', 'focus', or 'kill'. Defaults to 'execute'." },
            project_path: { type: 'string', description: "Absolute path to the project directory. This is a mandatory field." },
            tag: { type: 'string', description: "Optional. A unique identifier for the session (e.g., \"ui-build\", \"api-server\"). If omitted, a tag will be derived from the project_path." },
            command: { type: 'string', description: "Optional, primarily for action: 'execute'. The shell command to execute. If action is 'execute' and command is empty or omitted, the session will be prepared (cleared, focused if applicable), but no new command is run." },
            background: { type: 'boolean', default: DEFAULT_BACKGROUND_EXECUTION, description: `If true, command is long-running (default: ${DEFAULT_BACKGROUND_EXECUTION}).` }, 
            lines: { type: 'number', default: DEFAULT_LINES, description: `Max recent output lines (default: ${DEFAULT_LINES}).` },
            timeout: { type: 'number', description: `Timeout in seconds. Defaults depend on background flag (FG: ${DEFAULT_FOREGROUND_COMPLETION_SECONDS}s, BG: ${DEFAULT_BACKGROUND_STARTUP_SECONDS}s).` },
            focus: { type: 'boolean', default: DEFAULT_FOCUS_ON_ACTION, description: `Bring terminal to front (default: ${DEFAULT_FOCUS_ON_ACTION}).` },
        },
        required: ['action', 'project_path'],
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

        const action = params.action;
        if (![ 'exec', 'read', 'list', 'info', 'focus', 'kill'].includes(action)) {
            return { success: false, message: `Error: Invalid action '${action}'. Must be one of exec, read, list, info, focus, kill.` };
        }
        
        const options = getCanonicalOptions(params as any);

        debugLog(`Canonical options after processing:`, options);

        const effectiveProjectPath = resolveEffectiveProjectPath(params.project_path, undefined /* TODO: pass requestContext if available */);
        if (!effectiveProjectPath) {
            return { success: false, message: `Error: project_path '${params.project_path}' could not be resolved or is invalid.` };
        }

        let commandOpt: string | undefined = typeof options.command === 'string' ? options.command : undefined;
        if (action === 'exec' && options.command === undefined) commandOpt = '';
        
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

        if (!tag && ['exec', 'read', 'kill', 'focus'].includes(action) && action !== 'list' && action !== 'info') {
            const errorMsg = 'Error: Could not determine a session tag even with a project_path. This indicates an internal issue.';
            console.error(errorMsg, { tagVal: options.tag, projPath: effectiveProjectPath });
            return { success: false, message: errorMsg };
        }
        
        const cliArgs: string[] = [action];
        if (tag) {
            if (action === 'list' && options.tag) { 
                /* Will be added as --tag option later */
            } else if (action !== 'list' && action !== 'info') {
                cliArgs.push(tag);
            }
        }

        if (effectiveProjectPath) {
            cliArgs.push('--project-path', effectiveProjectPath);
        }
        if (commandOpt !== undefined && action === 'exec') { 
            cliArgs.push('--command', commandOpt);
        }
        
        if (action === 'exec' || action === 'read') {
            cliArgs.push('--lines', lines.toString());
        }
        
        const focusModeCli = focus ? 'force-focus' : 'no-focus'; 
        if (['exec', 'read', 'kill', 'focus'].includes(action)) {
            cliArgs.push('--focus-mode', focusModeCli);
        }

        if (action === 'exec') {
            if (background) {
                cliArgs.push('--background');
            }
            if (timeoutOverride !== undefined) {
                 cliArgs.push('--timeout', timeoutOverride.toString());
            }
        }
        
        if (action === 'list' || action === 'info') {
            cliArgs.push('--json');
        }
        if (action === 'list' && tag && options.tag) { 
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

            if (result.cancelled) {
                return { success: false, message: 'Terminator action cancelled by request.' };
            }
            if (result.internalTimeoutHit) {
                return { success: false, message: 'Terminator Swift CLI unresponsive and was terminated by the wrapper.' };
            }

            if (result.exitCode === null) {
                // Process crashed or was killed without proper exit
                let errMsg = result.stderr.trim() || result.stdout.trim() || 'Swift CLI process terminated unexpectedly';
                if (errMsg.includes('Permission denied') || errMsg.includes('not authorized')) {
                    errMsg += '. Please grant Terminal/iTerm automation permissions in System Settings > Privacy & Security > Automation';
                }
                return { success: false, message: `Terminator Error: ${errMsg}` };
            } else if (result.exitCode === 0) {
                const message = formatCliOutputForAI(action, result, commandOpt, tag, background, timeoutOverride);
                return { success: true, message };
            } else {
                let errMsg = result.stderr.trim() || result.stdout.trim() || 'Unknown error from Swift CLI';
                if (result.exitCode === 2) errMsg = `Configuration Error: ${errMsg}`;
                else if (result.exitCode === 3) errMsg = `AppleScript Communication Error: ${errMsg}`;
                else if (result.exitCode === 4) errMsg = `Process Control Error: ${errMsg}`;
                else if (result.exitCode === 5) errMsg = `Invalid CLI Arguments/Usage: ${errMsg}`;
                else if (result.exitCode === 6) errMsg = `Unsupported Operation for App: ${errMsg}`;
                else if (result.exitCode === 7) errMsg = `File/IO Error: ${errMsg}`;
                return { success: false, message: `Terminator Error (Swift CLI Code ${result.exitCode}): ${errMsg}` };
            }
        } catch (error: any) {
            debugLog('Error invoking or processing Swift CLI result:', error);
            return { success: false, message: `Terminator plugin internal error: ${error.message}` };
        }
    }
}; 