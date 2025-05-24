import { McpContext } from 'modelcontextprotocol'; // For McpContext
import { SwiftCLIResult } from './swift-cli'; // For SwiftCLIResult
import { debugLog, DEFAULT_BACKGROUND_STARTUP_SECONDS, DEFAULT_FOREGROUND_COMPLETION_SECONDS } from './config'; // For logging and defaults
import * as path from 'path'; // For path.basename, path.sep, path.isAbsolute
import * as fs from 'fs'; // For fs.statSync

export function sanitizeTag(rawTag: string): string {
    if (!rawTag) return '';
    // SDD 3.1.2: Alphanumeric, underscore, hyphen, max 64 chars.
    return rawTag.replace(/[^a-zA-Z0-9_\-]/g, '_').substring(0, 64);
}

export function resolveEffectiveProjectPath(currentPath: string | undefined, context: McpContext): string | undefined {
    let effectivePath = currentPath;
    if (!effectivePath && context?.requestContext?.roots?.length > 0) {
        const firstFileRoot = context.requestContext.roots.find((r: any) => r.uri?.scheme === 'file' && r.uri?.path && r.uri.path.length > 0);
        if (firstFileRoot) {
            effectivePath = firstFileRoot.uri.path;
            debugLog(`[Utils] Resolved effectiveProjectPath from MCP context: ${effectivePath}`);
        }
    }
    if (!effectivePath) {
        const envProjectPaths = ['CURSOR_ACTIVE_PROJECT_ROOT', 'VSCODE_PROJECT_ROOT', 'TERMINATOR_MCP_PROJECT_ROOT'];
        for (const envVar of envProjectPaths) {
            const envPathValue = process.env[envVar];
            if (envPathValue && envPathValue.trim() !== '') {
                if (path.isAbsolute(envPathValue)) {
                    try {
                        const stats = fs.statSync(envPathValue);
                        if (stats.isDirectory()) {
                            effectivePath = envPathValue;
                            debugLog(`[Utils] Resolved effectiveProjectPath from ENV var ${envVar}: ${effectivePath}`);
                            break;
                        }
                    } catch (e:any) { /* ignore */ }
                }
            }
        }
    }
    if (!effectivePath) {
        debugLog('[Utils] No effectiveProjectPath could be determined.');
    }
    return effectivePath;
}

export function resolveDefaultTag(currentTag: string | undefined, projectPath: string | undefined): string | undefined {
    let resolvedTag = currentTag;
    if (typeof resolvedTag === 'string' && resolvedTag.trim() === '') { // Treat empty string tag as undefined
        resolvedTag = undefined;
    }
    if (!resolvedTag && projectPath) {
        let base = path.basename(projectPath);
        if (base === '/' || base === '') {
            const parts = projectPath.split(path.sep).filter(p => p !== '');
            base = parts.length > 1 ? parts[parts.length - 2] : (parts.length === 1 ? parts[0] : '');
        }
        resolvedTag = sanitizeTag(base);
        if (!resolvedTag || resolvedTag === '_') { 
            resolvedTag = 'default_project_tag'; 
        }
        debugLog(`[Utils] Derived tag '${resolvedTag}' from projectPath '${projectPath}'`);
    }
    return resolvedTag;
}

export function formatCliOutputForAI(
    action: string, 
    cliResult: SwiftCLIResult, 
    command: string | undefined, 
    tag: string | undefined, 
    isBackground: boolean, // Need to know if it was a background exec for timeout message
    timeoutOverride?: number // User specified timeout
): string {
    const { stdout, stderr, exitCode } = cliResult;
    const stdoutTrimmed = stdout.trim();
    const stderrTrimmed = stderr.trim();

    if (action === 'list') {
        try {
            const sessions = JSON.parse(stdoutTrimmed);
            if (Array.isArray(sessions)) {
                if (sessions.length === 0) return "Terminator: No active sessions found.";
                const sessionDescriptions = sessions.map((s: any, index: number) => 
                    // SDD 3.1.4: "{index}. 🤖💥 {project_name} / {task_tag} ({is_busy ? 'Busy' : 'Idle'})"
                    `${index + 1}. 🤖💥 ${s.project_name || 'General'} / ${s.task_tag || s.session_identifier || 'UnknownSession'} (${s.is_busy ? 'Busy' : 'Idle'})`
                ).join('. ');
                return `Terminator: Found ${sessions.length} session(s). ${sessionDescriptions}.`;
            }
        } catch (e) {
            debugLog(`[Utils] Failed to parse JSON for list: ${e}. Raw: ${stdoutTrimmed}`);
            return `Terminator: 'list' completed, but output parsing failed. Raw: ${stdoutTrimmed}`;
        }
    }

    if (action === 'info') {
        try {
            const infoData = JSON.parse(stdoutTrimmed);
            const config = infoData.active_configuration;
            const managedSessions = infoData.managed_sessions || [];
            let msg = `Terminator v${infoData.version}.`;
            if (config) {
                msg += ` Config: App=${config.TERMINATOR_APP || 'N/A'}, Grouping=${config.TERMINATOR_WINDOW_GROUPING || 'N/A'}.`;
            }
            msg += ` Sessions: ${managedSessions.length}.`;
            if (managedSessions.length > 0) {
                const sessionDescriptions = managedSessions.map((s: any, index: number) => 
                    `${index + 1}. 🤖💥 ${s.project_name || 'General'} / ${s.task_tag || s.session_identifier || 'UnknownSession'} (${s.is_busy ? 'Busy' : 'Idle'})`
                ).join('. ');
                msg += ` Details: ${sessionDescriptions}.`;
            }
            return msg;
        } catch (e) {
            debugLog(`[Utils] Failed to parse JSON for info: ${e}. Raw: ${stdoutTrimmed}`);
            return `Terminator: 'info' completed, but output parsing failed. Raw: ${stdoutTrimmed}`;
        }
    }

    if (action === 'kill') {
        return `Terminator: Process in session '${tag || "Unknown"}' ${exitCode === 0 ? 'successfully targeted for termination' : 'could not be killed (or was already gone)'}. Output: ${stdoutTrimmed || stderrTrimmed || 'No output'}`.trim();
    }

    if (action === 'focus') {
        return `Terminator: Session '${tag || "Unknown"}' ${exitCode === 0 ? 'focused' : 'could not be focused'}. Output: ${stdoutTrimmed || stderrTrimmed || 'No output'}`.trim();
    }

    if (action === 'exec') {
        if (command === '') {
            return `Terminator: Session '${tag}' prepared.`;
        }
        // Check for timeout markers in Swift CLI output, even if exit code is 0
        const outputIndicatesTimeout = stdoutTrimmed.toLowerCase().includes('execution timed out') || stderrTrimmed.toLowerCase().includes('execution timed out');
        if (outputIndicatesTimeout) {
            const timeoutVal = timeoutOverride ?? (isBackground ? DEFAULT_BACKGROUND_STARTUP_SECONDS : DEFAULT_FOREGROUND_COMPLETION_SECONDS);
            return `Terminator: Command timed out after ${timeoutVal}s in session '${tag}'. Output (if any):
${stdoutTrimmed}`.trim();
        }
        // Standard successful exec
        return `Terminator: Command executed in session '${tag}'. Output:
${stdoutTrimmed || (stderrTrimmed ? "Error Output: " + stderrTrimmed : "No output")}`.trim();
    }
    
    // Default for other successful actions or if stdout is present
    return stdoutTrimmed || `Terminator: Action '${action}' completed successfully.`;
} 