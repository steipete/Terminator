import { describe, it, expect, beforeEach, vi } from 'vitest';
import { spawn } from 'child_process';
import { invokeSwiftCLI, SWIFT_CLI_PATH } from '../swift-cli.js';

vi.mock('child_process');
vi.mock('../logger.js');

describe('swift-cli', () => {
    let mockChildProcess: any;
    let mockContext: any;

    beforeEach(() => {
        vi.clearAllMocks();
        
        mockChildProcess = {
            stdout: { on: vi.fn() },
            stderr: { on: vi.fn() },
            on: vi.fn(),
            kill: vi.fn()
        };
        
        mockContext = {
            abortSignal: {
                addEventListener: vi.fn(),
                removeEventListener: vi.fn(),
                aborted: false
            }
        };
        
        vi.mocked(spawn).mockReturnValue(mockChildProcess as any);
    });

    describe('invokeSwiftCLI', () => {
        it('should spawn Swift CLI with correct arguments', async () => {
            const args = ['exec', 'test-tag', '--command', 'echo hello'];
            const env = { TERMINATOR_APP: 'iTerm' };
            
            // Set up successful execution
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    setTimeout(() => handler(0, null), 0);
                }
            });
            mockChildProcess.stdout.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'data') {
                    handler(Buffer.from('{"execResult": {"output": "hello"}}'));
                }
            });
            
            const result = await invokeSwiftCLI(args, env, mockContext, 120000);
            
            expect(spawn).toHaveBeenCalledWith(
                SWIFT_CLI_PATH,
                args,
                expect.objectContaining({
                    env: expect.objectContaining(env)
                })
            );
            expect(result.exitCode).toBe(0);
            expect(result.stdout).toContain('execResult');
        });

        it('should handle stderr output', async () => {
            const args = ['exec', 'test-tag'];
            const errorMessage = 'Error: Something went wrong';
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    setTimeout(() => handler(1, null), 0);
                }
            });
            mockChildProcess.stderr.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'data') {
                    handler(Buffer.from(errorMessage));
                }
            });
            
            const result = await invokeSwiftCLI(args, {}, mockContext, 120000);
            
            expect(result.exitCode).toBe(1);
            expect(result.stderr).toBe(errorMessage);
        });

        it('should handle process errors', async () => {
            const args = ['exec', 'test-tag'];
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'error') {
                    handler(new Error('Spawn error'));
                } else if (event === 'close') {
                    setTimeout(() => handler(null, null), 0);
                }
            });
            
            const result = await invokeSwiftCLI(args, {}, mockContext, 120000);
            
            expect(result.exitCode).toBeNull();
            expect(result.stderr).toContain('Spawn error');
        });

        it('should handle cancellation via abort signal', async () => {
            const args = ['exec', 'test-tag'];
            
            mockContext.abortSignal.addEventListener.mockImplementation((event: string, handler: Function) => {
                if (event === 'abort') {
                    // Simulate abort after a short delay
                    setTimeout(() => {
                        mockContext.abortSignal.aborted = true;
                        handler();
                    }, 10);
                }
            });
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    // Simulate delayed close
                    setTimeout(() => handler(143, null), 100);
                }
            });
            
            const result = await invokeSwiftCLI(args, {}, mockContext, 120000);
            
            expect(result.cancelled).toBe(true);
            expect(mockChildProcess.kill).toHaveBeenCalledWith('SIGTERM');
        });

        it('should handle internal timeout', async () => {
            const args = ['exec', 'test-tag'];
            const timeout = 100; // 100ms timeout
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    // Never close - simulate hanging process
                    // The timeout should trigger first
                }
            });
            
            const result = await invokeSwiftCLI(args, {}, mockContext, timeout);
            
            await new Promise(resolve => setTimeout(resolve, timeout + 50));
            
            expect(result.internalTimeoutHit).toBe(true);
            expect(mockChildProcess.kill).toHaveBeenCalledWith('SIGKILL');
        });

        it('should include PATH in environment', async () => {
            const args = ['list'];
            const customEnv = { CUSTOM_VAR: 'value' };
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    handler(0, null);
                }
            });
            
            await invokeSwiftCLI(args, customEnv, mockContext, 120000);
            
            expect(spawn).toHaveBeenCalledWith(
                SWIFT_CLI_PATH,
                args,
                expect.objectContaining({
                    env: expect.objectContaining({
                        PATH: process.env.PATH,
                        CUSTOM_VAR: 'value'
                    })
                })
            );
        });

        it('should handle signals correctly', async () => {
            const args = ['kill', 'test-tag'];
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    handler(null, 'SIGTERM');
                }
            });
            
            const result = await invokeSwiftCLI(args, {}, mockContext, 120000);
            
            expect(result.exitCode).toBeNull();
        });

        it('should accumulate stdout and stderr data', async () => {
            const args = ['read', 'test-tag'];
            
            mockChildProcess.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'close') {
                    setTimeout(() => handler(0, null), 50);
                }
            });
            
            mockChildProcess.stdout.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'data') {
                    handler(Buffer.from('First chunk'));
                    handler(Buffer.from(' Second chunk'));
                }
            });
            
            mockChildProcess.stderr.on.mockImplementation((event: string, handler: Function) => {
                if (event === 'data') {
                    handler(Buffer.from('Error 1'));
                    handler(Buffer.from(' Error 2'));
                }
            });
            
            const result = await invokeSwiftCLI(args, {}, mockContext, 120000);
            
            expect(result.stdout).toBe('First chunk Second chunk');
            expect(result.stderr).toBe('Error 1 Error 2');
        });
    });

    describe('SWIFT_CLI_PATH', () => {
        it('should be defined', () => {
            expect(SWIFT_CLI_PATH).toBeDefined();
            expect(SWIFT_CLI_PATH).toContain('terminator');
        });
    });
});