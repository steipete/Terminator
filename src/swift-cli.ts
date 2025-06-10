// Handles the direct invocation and process management of the Swift CLI 'terminator' binary.
// Now using execa for better error handling and cleaner code.
import { execa, ExecaError } from 'execa';
import errno from 'errno';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { debugLog } from './config.js';
import { SdkCallContext } from './types.js';
import { parseAndLogSwiftOutput, createSwiftLogProcessor } from './swift-log-parser.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const SWIFT_CLI_NAME = 'terminator';
export const SWIFT_CLI_PATH = process.env.TERMINATOR_CLI_PATH || path.resolve(__dirname, '..', 'bin', SWIFT_CLI_NAME);

export interface SwiftCLIResult {
    stdout: string;
    stderr: string;
    exitCode: number | null;
    cancelled: boolean;
    internalTimeoutHit: boolean;
}

// Note: We now use responsibility_spawnattrs_setdisclaim in the Swift CLI
// to make it self-responsible, which should trigger the permission dialog properly

export async function invokeSwiftCLI(
    cliArgs: string[], 
    terminatorEnv: Record<string, string>, 
    mcpContext: SdkCallContext, 
    wrapperTimeoutMs: number
): Promise<SwiftCLIResult> {
    debugLog(`Invoking Swift CLI: ${SWIFT_CLI_PATH} ${cliArgs.join(' ')} with env:`, terminatorEnv);
    
    // Swift CLI now handles permission dialog triggering internally via responsibility disclaimer
    
    const controller = new AbortController();
    let mcpCancelled = false;
    let internalTimeoutHit = false;
    
    // Handle MCP cancellation
    const mcpCancellationListener = () => {
        debugLog('MCP Host signalled cancellation.');
        mcpCancelled = true;
        controller.abort();
    };
    
    if (mcpContext.abortSignal) {
        if (mcpContext.abortSignal.aborted) {
            return { stdout: '', stderr: '', exitCode: null, cancelled: true, internalTimeoutHit: false };
        }
        mcpContext.abortSignal.addEventListener('abort', mcpCancellationListener);
    }
    
    // Set up internal timeout
    const timeoutId = setTimeout(() => {
        if (!mcpCancelled) {
            debugLog(`Swift CLI process exceeded internal wrapper timeout of ${wrapperTimeoutMs}ms. Killing.`);
            internalTimeoutHit = true;
            controller.abort();
        }
    }, wrapperTimeoutMs);
    
    try {
        const result = await execa(SWIFT_CLI_PATH, cliArgs, {
            env: { ...process.env, ...terminatorEnv },
            cwd: path.resolve(__dirname, '..'),
            cancelSignal: controller.signal, // Changed from 'signal' to 'cancelSignal' in newer execa versions
            reject: false, // Don't throw on non-zero exit codes
            all: false, // Keep stdout and stderr separate for log parsing
            buffer: true,
        });
        
        // Parse and forward Swift logs from stderr to pino
        let filteredStderr = result.stderr || '';
        if (filteredStderr) {
            parseAndLogSwiftOutput(filteredStderr);
            
            // Filter out Swift log lines from stderr to avoid polluting client output
            const logPattern = /^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\s+(\w+)\s+([^:]+):(\d+)\s+([^\]]+)\]\s+(.*)$/;
            const lines = filteredStderr.split('\n');
            const nonLogLines = lines.filter(line => !line.match(logPattern));
            filteredStderr = nonLogLines.join('\n').trim();
        }
        
        clearTimeout(timeoutId);
        
        // Process stdout for JSON commands
        let processedStdout = result.stdout || '';
        if (cliArgs.includes('info') && cliArgs.includes('--json')) {
            const jsonStartIndex = processedStdout.indexOf('{');
            if (jsonStartIndex !== -1) {
                processedStdout = processedStdout.substring(jsonStartIndex);
                debugLog('Extracted JSON from Swift CLI stdout:', processedStdout.trim());
            } else {
                debugLog("Could not find start of JSON ('{') in info command stdout. Using raw.");
            }
        } else if (cliArgs.includes('sessions') && cliArgs.includes('--json')) {
            const jsonStartIndex = processedStdout.indexOf('[');
            if (jsonStartIndex !== -1) {
                processedStdout = processedStdout.substring(jsonStartIndex);
                debugLog('Extracted JSON array from Swift CLI stdout:', processedStdout.trim());
            } else {
                debugLog("Could not find start of JSON array ('[') in sessions command stdout. Using raw.");
            }
        }
        
        debugLog(`Swift CLI exited with code ${result.exitCode}.`);
        
        return {
            stdout: processedStdout,
            stderr: filteredStderr,
            exitCode: result.exitCode ?? null,
            cancelled: false,
            internalTimeoutHit: false
        };
        
    } catch (error) {
        clearTimeout(timeoutId);
        
        // Handle aborted processes
        if (controller.signal.aborted) {
            if (mcpCancelled) {
                return { stdout: '', stderr: '', exitCode: null, cancelled: true, internalTimeoutHit: false };
            } else if (internalTimeoutHit) {
                return { stdout: '', stderr: '', exitCode: null, cancelled: false, internalTimeoutHit: true };
            }
        }
        
        // Handle execa errors
        if (error instanceof Error) {
            const execaError = error as ExecaError;
            
            // Build detailed error message for spawn errors
            let errorInfo = '';
            if ('code' in execaError) {
                // Map errno codes to friendly messages
                const errnoInfo = errno.code[execaError.code as keyof typeof errno.code];
                const friendlyMessage = errnoInfo ? `${errnoInfo.code} - ${errnoInfo.description}` : execaError.code;
                
                errorInfo = `Process spawn error: ${friendlyMessage}`;
                
                // Add specific guidance based on error code
                switch (execaError.code) {
                    case 'ENOENT':
                        errorInfo = `Swift CLI binary not found at ${SWIFT_CLI_PATH}`;
                        break;
                    case 'EACCES':
                        errorInfo = `Swift CLI binary not executable. Run: chmod +x ${SWIFT_CLI_PATH}`;
                        break;
                    case 'EPERM':
                        errorInfo = `Permission denied executing Swift CLI`;
                        break;
                }
            }
            
            // Log detailed error information
            debugLog('Failed to execute Swift CLI:', {
                message: execaError.message,
                code: 'code' in execaError ? execaError.code : undefined,
                exitCode: execaError.exitCode,
                signal: execaError.signal,
                signalDescription: execaError.signalDescription,
                stdout: typeof execaError.stdout === 'string' ? execaError.stdout.substring(0, 200) : undefined,
                stderr: typeof execaError.stderr === 'string' ? execaError.stderr.substring(0, 200) : undefined,
                command: execaError.command,
                escapedCommand: execaError.escapedCommand,
                failed: execaError.failed,
                timedOut: execaError.timedOut,
                isCanceled: execaError.isCanceled
            });
            
            // Filter Swift logs from error stderr as well
            let errorStderr = typeof execaError.stderr === 'string' ? execaError.stderr : '';
            if (errorStderr) {
                // Parse logs before filtering
                parseAndLogSwiftOutput(errorStderr);
                
                // Filter out Swift log lines
                const logPattern = /^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\s+(\w+)\s+([^:]+):(\d+)\s+([^\]]+)\]\s+(.*)$/;
                const lines = errorStderr.split('\n');
                const nonLogLines = lines.filter(line => !line.match(logPattern));
                errorStderr = nonLogLines.join('\n').trim();
            }
            
            return {
                stdout: typeof execaError.stdout === 'string' ? execaError.stdout : '',
                stderr: errorStderr + (errorInfo ? `\n${errorInfo}` : ''),
                exitCode: execaError.exitCode ?? null,
                cancelled: false,
                internalTimeoutHit: false
            };
        }
        
        // Unknown error type
        return {
            stdout: '',
            stderr: `Unknown error executing Swift CLI: ${error}`,
            exitCode: null,
            cancelled: false,
            internalTimeoutHit: false
        };
        
    } finally {
        // Clean up event listener
        if (mcpContext.abortSignal && mcpCancellationListener) {
            try {
                mcpContext.abortSignal.removeEventListener('abort', mcpCancellationListener);
            } catch (e) {
                debugLog("Minor error removing abort listener:", e);
            }
        }
    }
}