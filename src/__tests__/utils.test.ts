import { describe, it, expect, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
    resolveEffectiveProjectPath,
    resolveDefaultTag,
    formatCliOutputForAI,
    extractOutputForAction
} from '../utils.js';

vi.mock('node:fs');
vi.mock('node:path');

describe('utils', () => {
    describe('resolveEffectiveProjectPath', () => {
        it('should return absolute path as-is', () => {
            const absolutePath = '/absolute/path/to/project';
            vi.mocked(path.isAbsolute).mockReturnValue(true);
            vi.mocked(fs.existsSync).mockReturnValue(true);
            vi.mocked(fs.lstatSync).mockReturnValue({ isDirectory: () => true } as any);
            
            expect(resolveEffectiveProjectPath(absolutePath, '/fallback')).toBe(absolutePath);
        });

        it('should resolve relative path from current directory', () => {
            const relativePath = './relative/path';
            const resolvedPath = '/resolved/absolute/path';
            vi.mocked(path.isAbsolute).mockReturnValue(false);
            vi.mocked(path.resolve).mockReturnValue(resolvedPath);
            vi.mocked(fs.existsSync).mockReturnValue(true);
            vi.mocked(fs.lstatSync).mockReturnValue({ isDirectory: () => true } as any);
            
            expect(resolveEffectiveProjectPath(relativePath, '/fallback')).toBe(resolvedPath);
        });

        it('should use fallback path when primary path is null', () => {
            const fallbackPath = '/fallback/path';
            vi.mocked(path.isAbsolute).mockReturnValue(true);
            vi.mocked(fs.existsSync).mockReturnValue(true);
            vi.mocked(fs.lstatSync).mockReturnValue({ isDirectory: () => true } as any);
            
            expect(resolveEffectiveProjectPath(null as any, fallbackPath)).toBe(fallbackPath);
        });

        it('should return null when path does not exist', () => {
            const nonExistentPath = '/non/existent/path';
            vi.mocked(path.isAbsolute).mockReturnValue(true);
            vi.mocked(fs.existsSync).mockReturnValue(false);
            
            expect(resolveEffectiveProjectPath(nonExistentPath, '/fallback')).toBeNull();
        });

        it('should return null when path is not a directory', () => {
            const filePath = '/path/to/file.txt';
            vi.mocked(path.isAbsolute).mockReturnValue(true);
            vi.mocked(fs.existsSync).mockReturnValue(true);
            vi.mocked(fs.lstatSync).mockReturnValue({ isDirectory: () => false } as any);
            
            expect(resolveEffectiveProjectPath(filePath, '/fallback')).toBeNull();
        });
    });

    describe('resolveDefaultTag', () => {
        it('should return tag value if provided', () => {
            expect(resolveDefaultTag('custom-tag', '/any/path')).toBe('custom-tag');
        });

        it('should return null if tag is empty string', () => {
            expect(resolveDefaultTag('', '/any/path')).toBeNull();
        });

        it('should generate tag from project path when tag is not provided', () => {
            vi.mocked(path.basename).mockReturnValue('project-name');
            expect(resolveDefaultTag(undefined, '/path/to/project-name')).toBe('project-name');
        });

        it('should return null when neither tag nor project path is provided', () => {
            expect(resolveDefaultTag(undefined, undefined)).toBeNull();
        });

        it('should handle numeric tag values', () => {
            expect(resolveDefaultTag(123 as any, '/any/path')).toBe('123');
        });
    });

    describe('extractOutputForAction', () => {
        it('should extract read output for action "read"', () => {
            const jsonData = { readOutput: 'test output' };
            expect(extractOutputForAction('read', jsonData)).toBe('test output');
        });

        it('should extract exec output for action "exec"', () => {
            const jsonData = { execResult: { output: 'exec output' } };
            expect(extractOutputForAction('exec', jsonData)).toBe('exec output');
        });

        it('should return formatted JSON for action "list"', () => {
            const jsonData = { sessions: ['session1', 'session2'] };
            expect(extractOutputForAction('list', jsonData)).toBe(JSON.stringify(jsonData, null, 2));
        });

        it('should return formatted JSON for action "info"', () => {
            const jsonData = { version: '1.0.0', app: 'iTerm' };
            expect(extractOutputForAction('info', jsonData)).toBe(JSON.stringify(jsonData, null, 2));
        });

        it('should return null for unsupported actions', () => {
            expect(extractOutputForAction('unsupported', {})).toBeNull();
        });
    });

    describe('formatCliOutputForAI', () => {
        const mockResult = {
            stdout: '',
            stderr: '',
            exitCode: 0,
            internalTimeoutHit: false,
            cancelled: false
        };

        it('should format exec output with command details', () => {
            const jsonOutput = JSON.stringify({ execResult: { output: 'Command output' } });
            const result = { ...mockResult, stdout: jsonOutput };
            
            const formatted = formatCliOutputForAI('exec', result, 'npm test', 'test-tag', false, 30);
            expect(formatted).toContain('Command output');
            expect(formatted).toContain('npm test');
            expect(formatted).toContain('test-tag');
        });

        it('should format read output', () => {
            const jsonOutput = JSON.stringify({ readOutput: 'Session output' });
            const result = { ...mockResult, stdout: jsonOutput };
            
            const formatted = formatCliOutputForAI('read', result, undefined, 'test-tag', false);
            expect(formatted).toContain('Session output');
        });

        it('should format list output as JSON', () => {
            const sessions = [{ tag: 'session1' }, { tag: 'session2' }];
            const jsonOutput = JSON.stringify(sessions);
            const result = { ...mockResult, stdout: jsonOutput };
            
            const formatted = formatCliOutputForAI('list', result, undefined, undefined, false);
            expect(formatted).toContain('session1');
            expect(formatted).toContain('session2');
        });

        it('should handle kill action output', () => {
            const result = { ...mockResult, stdout: 'Process killed' };
            
            const formatted = formatCliOutputForAI('kill', result, undefined, 'test-tag', false);
            expect(formatted).toContain('test-tag');
            expect(formatted).toContain('killed');
        });

        it('should handle focus action output', () => {
            const result = { ...mockResult, stdout: 'Window focused' };
            
            const formatted = formatCliOutputForAI('focus', result, undefined, 'test-tag', false);
            expect(formatted).toContain('test-tag');
            expect(formatted).toContain('focused');
        });

        it('should handle JSON parsing errors gracefully', () => {
            const result = { ...mockResult, stdout: 'Invalid JSON' };
            
            const formatted = formatCliOutputForAI('exec', result, 'echo test', 'test-tag', false);
            expect(formatted).toContain('Invalid JSON');
        });

        it('should include background execution details', () => {
            const jsonOutput = JSON.stringify({ execResult: { output: 'Background output' } });
            const result = { ...mockResult, stdout: jsonOutput };
            
            const formatted = formatCliOutputForAI('exec', result, 'npm start', 'test-tag', true);
            expect(formatted).toContain('background');
        });
    });
});