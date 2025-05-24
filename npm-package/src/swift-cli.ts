// Handles the direct invocation and process management of the Swift CLI 'terminator' binary.
// Includes logic for spawning the process, handling stdout/stderr, cancellation, and timeouts.
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';
import { McpContext } from 'modelcontextprotocol'; // For context.signal
import { debugLog } from './config'; // For logging

export const SWIFT_CLI_NAME = 'terminator';
export const SWIFT_CLI_PATH = path.resolve(__dirname, '..', 'swift-bin', SWIFT_CLI_NAME);

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
    mcpContext: McpContext, // For cancellation signal
    wrapperTimeoutMs: number
): Promise<SwiftCLIResult> {
    debugLog(`Invoking Swift CLI: ${SWIFT_CLI_PATH} ${cliArgs.join(' ')} with env:`, terminatorEnv);
    
    let swiftProcess: ChildProcess | null = null;
    let internalTimeoutId: NodeJS.Timeout | null = null;
    let mcpCancellationListener: (() => void) | null = null;

    const executionPromise = new Promise<SwiftCLIResult>((resolve) => {
        swiftProcess = spawn(SWIFT_CLI_PATH, cliArgs, { env: terminatorEnv });

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

        swiftProcess.on('error', (err) => {
            if (mcpCancelled || internalTimeoutHit) return; 
            if (internalTimeoutId) clearTimeout(internalTimeoutId);
            debugLog('Failed to start Swift CLI.', err);
            resolve({ stdout: stdoutData, stderr: stderrData, exitCode: null, cancelled: false, internalTimeoutHit });
        });

        swiftProcess.on('close', (code) => {
            if (mcpCancelled || internalTimeoutHit) return; 
            if (internalTimeoutId) clearTimeout(internalTimeoutId);
            debugLog(`Swift CLI exited with code ${code}.`);
            resolve({ stdout: stdoutData, stderr: stderrData, exitCode: code, cancelled: false, internalTimeoutHit });
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
                    resolve({ 
                        stdout: stdoutData, 
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