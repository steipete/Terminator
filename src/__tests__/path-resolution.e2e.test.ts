import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { terminatorTool } from '../tool.js';
import { TerminatorExecuteParams, SdkCallContext } from '../types.js';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

// Mock the swift-cli module
vi.mock('../swift-cli.js', () => ({
    invokeSwiftCLI: vi.fn(),
    SWIFT_CLI_PATH: '/mock/path/to/swift/cli'
}));

const { invokeSwiftCLI } = await import('../swift-cli.js');
const mockedInvokeSwiftCLI = vi.mocked(invokeSwiftCLI);

describe('Path Resolution E2E Tests', () => {
    const mockContext: SdkCallContext = {
        abortSignal: new AbortController().signal
    };
    
    let testDir: string;
    
    beforeEach(() => {
        vi.clearAllMocks();
        
        // Create a temporary test directory
        testDir = path.join(os.tmpdir(), `terminator-path-test-${Date.now()}`);
        fs.mkdirSync(testDir, { recursive: true });
        
        // Set up default mock response
        mockedInvokeSwiftCLI.mockResolvedValue({
            stdout: '[]',
            stderr: '',
            exitCode: 0,
            cancelled: false,
            internalTimeoutHit: false
        });
    });
    
    afterEach(() => {
        // Clean up test directory
        if (fs.existsSync(testDir)) {
            fs.rmSync(testDir, { recursive: true, force: true });
        }
    });
    
    describe('Symlink handling', () => {
        it('should handle /tmp directory (symlink on macOS)', async () => {
            const params: TerminatorExecuteParams = {
                action: 'sessions',
                project_path: '/tmp'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            expect(result.message).not.toContain('could not be resolved');
            
            // Verify the CLI was called with /tmp
            expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
            const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
            expect(calledArgs).toContain('--project-path');
            expect(calledArgs).toContain('/tmp');
        });
        
        it('should handle other macOS symlinks', async () => {
            const symlinks = ['/var', '/etc'];
            
            for (const symlink of symlinks) {
                vi.clearAllMocks();
                
                const params: TerminatorExecuteParams = {
                    action: 'info',
                    project_path: symlink
                };
                
                const result = await terminatorTool.handler(params, mockContext);
                
                if (fs.existsSync(symlink)) {
                    expect(result.success).toBe(true);
                    expect(result.message).not.toContain('could not be resolved');
                }
            }
        });
    });
    
    describe('Tilde expansion', () => {
        it('should expand ~/Desktop to user home directory', async () => {
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: '~/Desktop',
                command: 'pwd'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            
            // Verify the expanded path was passed to CLI
            const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
            const projectPathIndex = calledArgs.indexOf('--project-path');
            const expandedPath = calledArgs[projectPathIndex + 1];
            
            expect(expandedPath).toBe(path.join(os.homedir(), 'Desktop'));
            expect(expandedPath).not.toContain('~');
        });
        
        it('should handle nested tilde paths', async () => {
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: '~/Documents/Projects/my-app',
                command: 'ls'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            
            const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
            const projectPathIndex = calledArgs.indexOf('--project-path');
            const expandedPath = calledArgs[projectPathIndex + 1];
            
            expect(expandedPath).toBe(path.join(os.homedir(), 'Documents', 'Projects', 'my-app'));
        });
    });
    
    describe('Directory creation', () => {
        it('should create non-existent directory', async () => {
            const newDir = path.join(testDir, 'new-project');
            expect(fs.existsSync(newDir)).toBe(false);
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: newDir,
                command: 'echo "test"'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            expect(fs.existsSync(newDir)).toBe(true);
            expect(fs.statSync(newDir).isDirectory()).toBe(true);
        });
        
        it('should create deeply nested directories', async () => {
            const deepDir = path.join(testDir, 'level1', 'level2', 'level3', 'level4');
            expect(fs.existsSync(deepDir)).toBe(false);
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: deepDir,
                command: 'pwd'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            expect(fs.existsSync(deepDir)).toBe(true);
        });
        
        it('should handle directory creation with tilde expansion', async () => {
            // Create a test path that doesn't exist yet
            const testPath = `~/terminator-test-${Date.now()}`;
            const expandedPath = path.join(os.homedir(), testPath.slice(2));
            
            // Ensure it doesn't exist
            if (fs.existsSync(expandedPath)) {
                fs.rmSync(expandedPath, { recursive: true });
            }
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: testPath,
                command: 'echo "created"'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            expect(fs.existsSync(expandedPath)).toBe(true);
            
            // Clean up
            fs.rmSync(expandedPath, { recursive: true });
        });
    });
    
    describe('Error cases', () => {
        it('should reject file paths (not directories)', async () => {
            const filePath = path.join(testDir, 'test.txt');
            fs.writeFileSync(filePath, 'test content');
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: filePath,
                command: 'echo "test"'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(false);
            expect(result.message).toContain('could not be resolved or is invalid');
        });
        
        it('should handle permission errors gracefully', async () => {
            // Try to use a protected system directory
            const protectedPath = '/System/Library/test-terminator';
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: protectedPath,
                command: 'echo "test"'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            // Should fail gracefully
            expect(result.success).toBe(false);
            expect(result.message).toContain('could not be resolved or is invalid');
        });
    });
    
    describe('Relative paths', () => {
        it('should resolve relative paths', async () => {
            // Create a subdirectory
            const subDir = path.join(testDir, 'subproject');
            fs.mkdirSync(subDir);
            
            // Test with a relative path that would resolve to the subdirectory
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: subDir,
                command: 'pwd'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            
            // Verify absolute path was passed to CLI
            const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
            const projectPathIndex = calledArgs.indexOf('--project-path');
            const resolvedPath = calledArgs[projectPathIndex + 1];
            
            expect(resolvedPath).toBe(subDir);
            expect(path.isAbsolute(resolvedPath)).toBe(true);
        });
        
        it('should convert relative paths to absolute paths', async () => {
            // Test with a relative path - our system should resolve it
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: './relative/path',
                command: 'pwd'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            // Should succeed and create the directory
            expect(result.success).toBe(true);
            
            // Verify absolute path was passed to CLI
            const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
            const projectPathIndex = calledArgs.indexOf('--project-path');
            const resolvedPath = calledArgs[projectPathIndex + 1];
            
            expect(path.isAbsolute(resolvedPath)).toBe(true);
            expect(resolvedPath).toContain('relative/path');
        });
    });
    
    describe('Special characters in paths', () => {
        it('should handle paths with spaces', async () => {
            const pathWithSpaces = path.join(testDir, 'My Projects & Tests');
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: pathWithSpaces,
                command: 'ls'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            expect(fs.existsSync(pathWithSpaces)).toBe(true);
        });
        
        it('should handle paths with unicode characters', async () => {
            const unicodePath = path.join(testDir, '日本語_проект_😀');
            
            const params: TerminatorExecuteParams = {
                action: 'execute',
                project_path: unicodePath,
                command: 'echo "unicode test"'
            };
            
            const result = await terminatorTool.handler(params, mockContext);
            
            expect(result.success).toBe(true);
            expect(fs.existsSync(unicodePath)).toBe(true);
        });
    });
});