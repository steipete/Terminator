import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { execa } from 'execa';
import { invokeSwiftCLI } from '../swift-cli.js';
import { parseAndLogSwiftOutput } from '../swift-log-parser.js';
import type { SdkCallContext } from '../types.js';

// Mock dependencies
vi.mock('execa');
vi.mock('../swift-log-parser.js', () => ({
    parseAndLogSwiftOutput: vi.fn()
}));
vi.mock('../logger.js', () => ({
    logger: {
        error: vi.fn(),
        info: vi.fn(),
        debug: vi.fn()
    }
}));

describe('Swift CLI Log Filtering', () => {
    let mockContext: SdkCallContext;
    
    beforeEach(() => {
        vi.clearAllMocks();
        mockContext = { abortSignal: undefined };
    });

    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('should filter Swift log lines from stderr in successful execution', async () => {
        const stderrWithLogs = `[2025-06-10T13:08:24.453Z INFO ProcessResponsibility.swift:33 disclaimParentResponsibility()] Attempting to re-spawn
[2025-06-10T13:08:24.454Z INFO ProcessResponsibility.swift:86 disclaimParentResponsibility()] Successfully spawned
Error: Missing expected argument '--tag <tag>'
Help:  --tag <tag>  Tag identifying the session.
[2025-06-10T13:08:24.463Z DEBUG Logger.swift:42 shutdown()] Logger shutting down.`;

        const mockResult = {
            stdout: 'Command output',
            stderr: stderrWithLogs,
            exitCode: 1,
            failed: false,
            timedOut: false,
            isCanceled: false,
            killed: false,
            command: 'terminator',
            escapedCommand: 'terminator',
            cwd: '/path',
            duration: 100
        };

        vi.mocked(execa).mockResolvedValue(mockResult as any);

        const result = await invokeSwiftCLI(['focus'], {}, mockContext, 5000);

        // Verify logs were parsed
        expect(parseAndLogSwiftOutput).toHaveBeenCalledWith(stderrWithLogs);

        // Verify logs were filtered from stderr
        expect(result.stderr).toBe(`Error: Missing expected argument '--tag <tag>'
Help:  --tag <tag>  Tag identifying the session.`);
        expect(result.stderr).not.toContain('ProcessResponsibility.swift');
        expect(result.stderr).not.toContain('Logger.swift');
    });

    it('should filter Swift log lines from stderr in error cases', async () => {
        const stderrWithLogs = `[2025-06-10T13:08:24.453Z ERROR App.swift:10 main()] Fatal error occurred
[2025-06-10T13:08:24.454Z DEBUG Logger.swift:42 shutdown()] Shutting down
Actual error message for user`;

        const mockError = new Error('Command failed') as any;
        mockError.exitCode = 1;
        mockError.stderr = stderrWithLogs;
        mockError.stdout = '';
        mockError.failed = true;
        mockError.timedOut = false;
        mockError.isCanceled = false;
        mockError.killed = false;
        mockError.command = 'terminator';
        mockError.escapedCommand = 'terminator';

        vi.mocked(execa).mockRejectedValue(mockError);

        const result = await invokeSwiftCLI(['exec'], {}, mockContext, 5000);

        // Verify logs were parsed before filtering
        expect(parseAndLogSwiftOutput).toHaveBeenCalledWith(stderrWithLogs);

        // Verify only actual error remains
        expect(result.stderr).toBe('Actual error message for user');
        expect(result.stderr).not.toContain('App.swift');
        expect(result.stderr).not.toContain('Logger.swift');
    });

    it('should handle empty stderr', async () => {
        const mockResult = {
            stdout: 'Output',
            stderr: '',
            exitCode: 0,
            failed: false,
            timedOut: false,
            isCanceled: false,
            killed: false,
            command: 'terminator',
            escapedCommand: 'terminator',
            cwd: '/path',
            duration: 100
        };

        vi.mocked(execa).mockResolvedValue(mockResult as any);

        const result = await invokeSwiftCLI(['info'], {}, mockContext, 5000);

        expect(parseAndLogSwiftOutput).not.toHaveBeenCalled();
        expect(result.stderr).toBe('');
    });

    it('should handle stderr with only log lines', async () => {
        const stderrOnlyLogs = `[2025-06-10T13:08:24.453Z INFO Test.swift:1 test()] Log line 1
[2025-06-10T13:08:24.454Z DEBUG Test.swift:2 test()] Log line 2
[2025-06-10T13:08:24.455Z TRACE Test.swift:3 test()] Log line 3`;

        const mockResult = {
            stdout: 'Output',
            stderr: stderrOnlyLogs,
            exitCode: 0,
            failed: false,
            timedOut: false,
            isCanceled: false,
            killed: false,
            command: 'terminator',
            escapedCommand: 'terminator',
            cwd: '/path',
            duration: 100
        };

        vi.mocked(execa).mockResolvedValue(mockResult as any);

        const result = await invokeSwiftCLI(['list'], {}, mockContext, 5000);

        expect(parseAndLogSwiftOutput).toHaveBeenCalledWith(stderrOnlyLogs);
        expect(result.stderr).toBe(''); // All lines filtered out
    });

    it('should preserve multi-line error messages', async () => {
        const stderrMixed = `[2025-06-10T13:08:24.453Z INFO Test.swift:1 test()] Starting
Error: Command failed
  Reason: Invalid parameters
  Solution: Check your input
[2025-06-10T13:08:24.454Z DEBUG Test.swift:2 test()] Finished`;

        const mockResult = {
            stdout: '',
            stderr: stderrMixed,
            exitCode: 1,
            failed: false,
            timedOut: false,
            isCanceled: false,
            killed: false,
            command: 'terminator',
            escapedCommand: 'terminator',
            cwd: '/path',
            duration: 100
        };

        vi.mocked(execa).mockResolvedValue(mockResult as any);

        const result = await invokeSwiftCLI(['exec'], {}, mockContext, 5000);

        expect(result.stderr).toBe(`Error: Command failed
  Reason: Invalid parameters
  Solution: Check your input`);
        expect(result.stderr).not.toContain('Test.swift');
    });

    it('should append spawn error info after filtering', async () => {
        const stderrWithLogs = `[2025-06-10T13:08:24.453Z ERROR Test.swift:1 test()] Error log
Some error output`;

        const mockError = new Error('spawn ENOENT') as any;
        mockError.code = 'ENOENT';
        mockError.stderr = stderrWithLogs;
        mockError.stdout = '';
        mockError.failed = true;

        vi.mocked(execa).mockRejectedValue(mockError);

        const result = await invokeSwiftCLI(['exec'], {}, mockContext, 5000);

        // Should have filtered stderr + spawn error info
        expect(result.stderr).toContain('Some error output');
        expect(result.stderr).toContain('Swift CLI binary not found at');
        expect(result.stderr).not.toContain('Test.swift');
    });
});