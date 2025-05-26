// Provides utility functions for the Terminator MCP tool, including tag sanitization,
// project path resolution, default tag generation, and formatting Swift CLI output for the AI.
import * as fs from 'node:fs';
import { SwiftCLIResult } from './swift-cli.js'; // For SwiftCLIResult
import { debugLog, DEFAULT_BACKGROUND_STARTUP_SECONDS, DEFAULT_FOREGROUND_COMPLETION_SECONDS } from './config.js'; // For logging and defaults
import * as path from 'node:path'; // For path.basename, path.sep, path.isAbsolute
import { RequestContextMeta } from './types.js';

export function sanitizeTag(rawTag: string): string {
    if (!rawTag) return '';
    // SDD 3.1.2: Alphanumeric, underscore, hyphen, max 64 chars.
    return rawTag.replace(/[^a-zA-Z0-9_\-]/g, '_').substring(0, 64);
}

export function resolveEffectiveProjectPath(currentPath: string | undefined, _requestMeta: RequestContextMeta | undefined): string | undefined {
    // According to spec.md section 3.1.2, `currentPath` (derived from AI's `project_path`) is mandatory and the sole source.
    // It must be an absolute path.
    if (!currentPath) {
        debugLog('[Utils] effectiveProjectPath error: currentPath (from AI project_path) is undefined.');
        return undefined; // This should be caught by the caller in tool.ts
    }

    if (!path.isAbsolute(currentPath)) {
        debugLog(`[Utils] effectiveProjectPath error: currentPath '${currentPath}' is not an absolute path.`);
        return undefined; // Caller in tool.ts will return an error message.
    }

    try {
        const stats = fs.statSync(currentPath);
        if (!stats.isDirectory()) {
            debugLog(`[Utils] effectiveProjectPath error: currentPath '${currentPath}' is not a directory.`);
            return undefined; // Caller in tool.ts will return an error message.
        }
    } catch (e:any) {
        debugLog(`[Utils] effectiveProjectPath error: fs.statSync failed for '${currentPath}'. Error: ${e.message}`);
        return undefined; // Caller in tool.ts will return an error message.
    }

    debugLog(`[Utils] Validated effectiveProjectPath: ${currentPath}`);
    return currentPath;
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
            debugLog(`[Utils] info action: raw stdoutTrimmed: >>>${stdoutTrimmed}<<<`);
            const infoData = JSON.parse(stdoutTrimmed);
            debugLog(`[Utils] info action: parsed infoData:`, infoData);

            const version = infoData.version;
            debugLog(`[Utils] info action: infoData.version:`, version);

            const config = infoData.configuration;
            debugLog(`[Utils] info action: infoData.configuration:`, config);

            const sessionsArray = infoData.sessions || [];
            debugLog(`[Utils] info action: infoData.sessions (or default []):`, sessionsArray);
            debugLog(`[Utils] info action: sessionsArray.length:`, sessionsArray.length);

            let msg = `Terminator v${version}.`;
            if (config) {
                msg += ` Config: App=${config.TERMINATOR_APP || 'N/A'}, Grouping=${config.TERMINATOR_WINDOW_GROUPING || 'N/A'}.`;
            }

            msg += ` Sessions: ${sessionsArray.length}.`; 
            
            if (sessionsArray.length > 0) {
                debugLog(`[Utils] info action: Processing ${sessionsArray.length} sessions.`);
                const sessionDescriptions = sessionsArray.map((sessionDetails: any, index: number) => {
                    debugLog(`[Utils] info action: Processing session ${index + 1}:`, sessionDetails);
                    const projectName = sessionDetails.project_name || 'General';
                    const taskTag = sessionDetails.task_tag || sessionDetails.session_identifier || 'UnknownSession';
                    const isBusy = sessionDetails.is_busy === undefined ? false : sessionDetails.is_busy;
                    const description = `${index + 1}. 🤖💥 ${projectName} / ${taskTag} (${isBusy ? 'Busy' : 'Idle'})`;
                    debugLog(`[Utils] info action: Session ${index + 1} description:`, description);
                    return description;
                }).join('. ');
                msg += ` Details: ${sessionDescriptions}.`;
            }
            debugLog(`[Utils] info action: Successfully formatted message:`, msg);
            return msg;
        } catch (e: any) {
            debugLog(`[Utils] CRITICAL ERROR in info parsing: ${e.message}. Stack: ${e.stack}. Raw input was: >>>${stdoutTrimmed}<<<`);
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