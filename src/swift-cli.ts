// Handles the direct invocation and process management of the Swift CLI 'terminator' binary.
// Includes logic for spawning the process, handling stdout/stderr, cancellation, and timeouts.
import { spawn, ChildProcess } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { debugLog } from './config.js'; // For logging
import * as fs from 'node:fs'; // Import fs
// import * as pty from 'node-pty'; // node-pty might have issues with ESM, let's see if it's used
import { SdkCallContext } from './types.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const SWIFT_CLI_NAME = 'terminator';
export const SWIFT_CLI_PATH = path.resolve(__dirname, '..', 'bin', SWIFT_CLI_NAME);

export interface SwiftCLIResult {
    stdout: string;
    stderr: string;
    exitCode: number | null;
    cancelled?: boolean;
    internalTimeoutHit?: boolean;
}

export function invokeSwiftCLI(
    cliArgs: string[], 
    terminatorEnv: Record<string, string>, 
    mcpContext: SdkCallContext, 
    wrapperTimeoutMs: number
): Promise<SwiftCLIResult> {
    debugLog(`Invoking Swift CLI: ${SWIFT_CLI_PATH} ${cliArgs.join(' ')} with env:`, terminatorEnv);
    
    let swiftProcess: ChildProcess | null = null;
    let internalTimeoutId: NodeJS.Timeout | null = null;
    let mcpCancellationListener: (() => void) | null = null;

    const executionPromise = new Promise<SwiftCLIResult>((resolve) => {
        debugLog(`[invokeSwiftCLI] About to spawn. Resolved SWIFT_CLI_PATH: ${SWIFT_CLI_PATH}`);
        debugLog(`[invokeSwiftCLI] Does SWIFT_CLI_PATH exist according to fs.existsSync? ${fs.existsSync(SWIFT_CLI_PATH)}`);
        swiftProcess = spawn(SWIFT_CLI_PATH, cliArgs, {
            env: { ...process.env, ...terminatorEnv },
            cwd: path.resolve(__dirname, '..') // Set CWD to project root
        });

        let stdoutData = '';
        let stderrData = '';
        let mcpCancelled = false;
        let internalTimeoutHit = false;

        mcpCancellationListener = () => {
            if (mcpCancelled) return;
            debugLog('MCP Host signalled cancellation.');
            mcpCancelled = true;
            if (internalTimeoutId) clearTimeout(internalTimeoutId);
            if (swiftProcess && !swiftProcess.killed) {
                debugLog('Attempting to SIGKILL Swift CLI process due to MCP cancellation.');
                swiftProcess.kill('SIGKILL'); 
            }
            // Resolve directly, on('close') might not fire or might be delayed
            resolve({ stdout: stdoutData, stderr: stderrData, exitCode: null, cancelled: true });
        };

        if (mcpContext.signal) {
            if (mcpContext.signal.aborted) {
                mcpCancellationListener(); // Call immediately if already aborted
                return;
            }
            mcpContext.signal.addEventListener('abort', mcpCancellationListener);
        }

        swiftProcess.stdout?.on('data', (data) => {
            stdoutData += data.toString();
            debugLog('Swift CLI stdout:', data.toString().trim());
        });

        swiftProcess.stderr?.on('data', (data) => {
            stderrData += data.toString();
            debugLog('Swift CLI stderr:', data.toString().trim());
        });

        swiftProcess.on('error', (err: any) => {
            if (mcpCancelled || internalTimeoutHit) return; 
            if (internalTimeoutId) clearTimeout(internalTimeoutId);
            debugLog('Failed to start Swift CLI.', err);
            
            // Add error details to stderr for better diagnostics
            let errorInfo = `Process spawn error: ${err.message || err}`;
            if (err.code === 'ENOENT') {
                errorInfo = `Swift CLI binary not found at ${SWIFT_CLI_PATH}`;
            } else if (err.code === 'EACCES') {
                errorInfo = `Swift CLI binary not executable. Run: chmod +x ${SWIFT_CLI_PATH}`;
            } else if (err.code === 'EPERM') {
                errorInfo = `Permission denied executing Swift CLI`;
            }
            
            stderrData += `\n${errorInfo}`;
            resolve({ stdout: stdoutData, stderr: stderrData, exitCode: null, cancelled: false, internalTimeoutHit });
        });

        swiftProcess.on('close', (code) => {
            if (mcpCancelled || internalTimeoutHit) return; 
            if (internalTimeoutId) clearTimeout(internalTimeoutId);
            debugLog(`Swift CLI exited with code ${code}.`);

            let processedStdout = stdoutData;
            // Check if this was a command expected to produce JSON
            // A more robust check might involve inspecting cliArgs more deeply or passing a flag
            if (cliArgs.includes('info') && cliArgs.includes('--json')) {
                const jsonStartIndex = stdoutData.indexOf('{');
                if (jsonStartIndex !== -1) {
                    processedStdout = stdoutData.substring(jsonStartIndex);
                    debugLog('Extracted JSON from Swift CLI stdout:', processedStdout.trim());
                } else {
                    debugLog("Could not find start of JSON ('{') in info command stdout. Using raw.");
                }
            } else if (cliArgs.includes('list') && cliArgs.includes('--json')) {
                const jsonStartIndex = stdoutData.indexOf('['); // list command outputs a JSON array
                if (jsonStartIndex !== -1) {
                    processedStdout = stdoutData.substring(jsonStartIndex);
                    debugLog('Extracted JSON array from Swift CLI stdout:', processedStdout.trim());
                } else {
                    debugLog("Could not find start of JSON array ('[') in list command stdout. Using raw.");
                }
            }

            resolve({ stdout: processedStdout, stderr: stderrData, exitCode: code, cancelled: false, internalTimeoutHit });
        });

        // Internal timeout for the Swift CLI process itself
        internalTimeoutId = setTimeout(() => {
            if (mcpCancelled || internalTimeoutHit) return;
            internalTimeoutHit = true;
            if (swiftProcess && !swiftProcess.killed) {
                debugLog(`Swift CLI process exceeded internal wrapper timeout of ${wrapperTimeoutMs}ms. Killing.`);
                swiftProcess.kill('SIGKILL');
            }
            // The 'close' event should eventually fire and resolve the promise.
            // To be safe, if close doesn't fire after a short delay, resolve with timeout status.
            // This secondary timeout is to prevent hangs if SIGKILL + close event fails to trigger 'close' promptly.
            setTimeout(() => {
                 if (!mcpCancelled) { // Check again in case MCP cancellation happened during this small delay
                    // Process stdout for JSON extraction here as well, in case of timeout before 'close'
                    let processedStdoutOnTimeout = stdoutData;
                    if (cliArgs.includes('info') && cliArgs.includes('--json')) {
                        const jsonStartIndex = stdoutData.indexOf('{');
                        if (jsonStartIndex !== -1) {
                            processedStdoutOnTimeout = stdoutData.substring(jsonStartIndex);
                        }
                    } else if (cliArgs.includes('list') && cliArgs.includes('--json')) {
                        const jsonStartIndex = stdoutData.indexOf('[');
                        if (jsonStartIndex !== -1) {
                            processedStdoutOnTimeout = stdoutData.substring(jsonStartIndex);
                        }
                    }
                    resolve({ 
                        stdout: processedStdoutOnTimeout, 
                        stderr: stderrData, 
                        exitCode: null, // Or last known code if any
                        cancelled: false, 
                        internalTimeoutHit: true 
                    });
                 }
            }, 1000); // Give 1 sec for SIGKILL to result in a 'close' event
        }, wrapperTimeoutMs);
    });

    return executionPromise.finally(() => {
        if (mcpContext.signal && mcpCancellationListener) {
            try {
                 mcpContext.signal.removeEventListener('abort', mcpCancellationListener);
            } catch (e) {
                debugLog("Minor error removing abort listener, possibly due to it not being standard on this Node version's AbortSignal.");
            }
        }
        if (internalTimeoutId) {
            clearTimeout(internalTimeoutId);
        }
    });
} 