// Defines the main MCP tool, 'terminator.execute', including its schema,
// description, and the central handler function that orchestrates calls to other modules.
import { McpTool, McpContext } from 'modelcontextprotocol';
import { TerminatorOptions, TerminatorExecuteParams, TerminatorResult } from './types'; 
import {
    CURRENT_TERMINAL_APP, 
    DEFAULT_BACKGROUND_STARTUP_SECONDS, 
    DEFAULT_FOREGROUND_COMPLETION_SECONDS, 
    DEFAULT_LINES, 
    DEFAULT_FOCUS_ON_ACTION,
    DEFAULT_BACKGROUND_EXECUTION, 
    getCanonicalOptions,
    debugLog
} from './config';
import { invokeSwiftCLI, SwiftCLIResult } from './swift-cli'; 
import {
    resolveEffectiveProjectPath,
    resolveDefaultTag,
    formatCliOutputForAI
} from './utils';

export const terminatorTool: McpTool<TerminatorExecuteParams, TerminatorResult> = {
    name: 'terminator.execute',
    description: `Manages macOS terminal sessions using the ${CURRENT_TERMINAL_APP} application. Ideal for running commands that might be long-running or could hang, as it isolates them to protect your workflow and allows for faster interaction. The session screen is automatically cleared before executing a new command or after a process is killed. Use this to execute shell commands, retrieve output, and manage terminal processes.`,
    inputSchema: {
        type: 'object',
        properties: {
            action: { type: 'string', enum: ['exec', 'read', 'list', 'info', 'focus', 'kill'] },
            options: {
                type: 'object',
                properties: {
                    projectPath: { type: 'string', description: "Absolute path to the project directory. If not provided, uses active IDE project or ENV vars." },
                    tag: { type: 'string', description: "Unique session identifier. Derived from projectPath if omitted. Required for exec, read, kill, focus." },
                    command: { type: 'string', description: "Shell command to execute (for action: exec)." },
                    background: { type: 'boolean', default: DEFAULT_BACKGROUND_EXECUTION, description: `If true, command is long-running (default: ${DEFAULT_BACKGROUND_EXECUTION}).` }, 
                    lines: { type: 'number', default: DEFAULT_LINES, description: `Max recent output lines (default: ${DEFAULT_LINES}).` },
                    timeout: { type: 'number', description: `Timeout in seconds. Defaults depend on background flag (FG: ${DEFAULT_FOREGROUND_COMPLETION_SECONDS}s, BG: ${DEFAULT_BACKGROUND_STARTUP_SECONDS}s).` },
                    focus: { type: 'boolean', default: DEFAULT_FOCUS_ON_ACTION, description: `Bring terminal to front (default: ${DEFAULT_FOCUS_ON_ACTION}).` },
                },
                additionalProperties: true, 
            },
        },
        required: ['action'],
    },
    outputSchema: {
        type: 'object',
        properties: {
            success: { type: 'boolean' },
            message: { type: 'string' },
        },
        required: ['success', 'message'],
    },
    async handler(params: TerminatorExecuteParams, context: McpContext): Promise<TerminatorResult> {
        debugLog(`Received action: ${params.action} with raw options:`, params.options);

        const action = params.action;
        if (![ 'exec', 'read', 'list', 'info', 'focus', 'kill'].includes(action)) {
            return { success: false, message: `Error: Invalid action '${action}'. Must be one of exec, read, list, info, focus, kill.` };
        }
        
        const rawOptions = params.options || {};
        const options = getCanonicalOptions(rawOptions);

        let projectPathOpt: string | undefined = typeof options.projectPath === 'string' ? options.projectPath : undefined;
        let commandOpt: string | undefined = typeof options.command === 'string' ? options.command : undefined;
        if (action === 'exec' && options.command === undefined) commandOpt = '';
        
        let lines = typeof options.lines === 'number' ? options.lines : DEFAULT_LINES;
        if (typeof options.lines === 'string') lines = parseInt(options.lines, 10) || DEFAULT_LINES;

        let background = typeof options.background === 'boolean' ? options.background : DEFAULT_BACKGROUND_EXECUTION;
        if (typeof options.background === 'string') background = ['true', '1', 't', 'yes', 'on'].includes(options.background.toLowerCase());

        let focus = typeof options.focus === 'boolean' ? options.focus : DEFAULT_FOCUS_ON_ACTION;
        if (typeof options.focus === 'string') focus = ['true', '1', 't', 'yes', 'on'].includes(options.focus.toLowerCase());

        let timeoutOverride = typeof options.timeout === 'number' ? options.timeout : undefined;
        if (typeof options.timeout === 'string') timeoutOverride = parseInt(options.timeout, 10) || undefined;

        const effectiveProjectPath = resolveEffectiveProjectPath(projectPathOpt, context);
        let tag = resolveDefaultTag(options.tag, effectiveProjectPath);

        if (!tag && ['exec', 'read', 'kill', 'focus'].includes(action)) {
             const errorMsg = 'Error: Tag is required for this action (exec, read, kill, focus) if projectPath is not provided or a default tag cannot be derived.';
             console.error(errorMsg);
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
             cliArgs.push('--execution-mode', background ? 'background' : 'foreground');
             const execTimeout = timeoutOverride ?? (background ? DEFAULT_BACKGROUND_STARTUP_SECONDS : DEFAULT_FOREGROUND_COMPLETION_SECONDS);
             cliArgs.push('--timeout-seconds', execTimeout.toString());
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

            if (result.exitCode === 0) {
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