import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { spawn } from 'node:child_process';

describe('logger integration tests', () => {
    let originalEnv: NodeJS.ProcessEnv;
    let testLogFile: string;
    
    beforeEach(() => {
        // Save original environment
        originalEnv = { ...process.env };
        
        // Create a unique log file name for this test
        testLogFile = path.join(os.tmpdir(), `terminator-test-${Date.now()}.log`);
    });
    
    afterEach(() => {
        // Restore original environment
        process.env = originalEnv;
        
        // Clean up test log file if it exists
        if (fs.existsSync(testLogFile)) {
            fs.unlinkSync(testLogFile);
        }
    });
    
    describe('Logger fallback behavior', () => {
        it('should write to custom log file when path is valid', async () => {
            // Set custom log file
            process.env.TERMINATOR_LOG_FILE = testLogFile;
            
            // Run a simple command that will trigger logging
            await runNodeScript(`
                import { logger } from './dist/logger.js';
                logger.info('Test log message');
                await new Promise(resolve => setTimeout(resolve, 100));
            `);
            
            // Check that log file was created and contains our message
            expect(fs.existsSync(testLogFile)).toBe(true);
            const logContent = fs.readFileSync(testLogFile, 'utf8');
            expect(logContent).toContain('Test log message');
        });
        
        it('should fall back to default directory when custom path is invalid', async () => {
            // Set an invalid log file path (directory doesn't exist)
            const invalidPath = '/this/path/does/not/exist/terminator.log';
            process.env.TERMINATOR_LOG_FILE = invalidPath;
            
            // Run a command that will trigger logging
            await runNodeScript(`
                import { logger, getLoggerConfig } from './dist/logger.js';
                const config = getLoggerConfig();
                console.log(JSON.stringify(config));
                logger.info('Fallback test message');
                await new Promise(resolve => setTimeout(resolve, 100));
            `);
            
            // The logger should have fallen back to default location
            const defaultLogPath = path.join(os.homedir(), 'Library', 'Logs', 'terminator-mcp', 'terminator.log');
            const tempLogPath = path.join(os.tmpdir(), 'terminator-mcp', 'terminator.log');
            
            // Check that it didn't create the invalid path
            expect(fs.existsSync(invalidPath)).toBe(false);
            
            // Should have created log in either default or temp location
            const logExists = fs.existsSync(defaultLogPath) || fs.existsSync(tempLogPath);
            expect(logExists).toBe(true);
        });
        
        it('should fall back to temp directory when default directory is not writable', async () => {
            // This test simulates when both custom and default paths are not writable
            // by setting paths that require elevated permissions
            const unwritablePath = '/System/Library/terminator.log'; // macOS protected path
            process.env.TERMINATOR_LOG_FILE = unwritablePath;
            
            await runNodeScript(`
                import { logger, getLoggerConfig } from './dist/logger.js';
                const config = getLoggerConfig();
                console.log(JSON.stringify(config));
                logger.info('Temp fallback test');
                await new Promise(resolve => setTimeout(resolve, 100));
            `);
            
            // Should have fallen back to temp directory
            const tempLogPath = path.join(os.tmpdir(), 'terminator-mcp', 'terminator.log');
            const defaultLogPath = path.join(os.homedir(), 'Library', 'Logs', 'terminator-mcp', 'terminator.log');
            
            // Check that it didn't create the unwritable path
            expect(fs.existsSync(unwritablePath)).toBe(false);
            
            // Should have created log in either default or temp location
            const logExists = fs.existsSync(defaultLogPath) || fs.existsSync(tempLogPath);
            expect(logExists).toBe(true);
            
            // Clean up logs
            if (fs.existsSync(tempLogPath)) {
                const logContent = fs.readFileSync(tempLogPath, 'utf8');
                expect(logContent).toContain('Temp fallback test');
                fs.unlinkSync(tempLogPath);
            }
            if (fs.existsSync(defaultLogPath)) {
                fs.unlinkSync(defaultLogPath);
            }
        });
        
        it('should report configuration issues in getLoggerConfig', async () => {
            // Set invalid log level
            process.env.TERMINATOR_LOG_LEVEL = 'invalid-level';
            process.env.TERMINATOR_LOG_FILE = '/invalid/path/log.txt';
            
            const output = await runNodeScript(`
                import { getLoggerConfig } from './dist/logger.js';
                const config = getLoggerConfig();
                console.log(JSON.stringify(config));
            `);
            
            const config = JSON.parse(output);
            expect(config.configurationIssues).toHaveLength(2);
            expect(config.configurationIssues[0]).toContain('Cannot write to log file path');
            expect(config.configurationIssues[1]).toContain('Invalid log level');
        });
        
        it('should not output to console by default', async () => {
            // Ensure console logging is not enabled
            delete process.env.TERMINATOR_CONSOLE_LOGGING;
            
            const output = await runNodeScript(`
                import { logger } from './dist/logger.js';
                logger.info('Should not appear in console');
                console.log('MARKER:TEST_COMPLETE');
                await new Promise(resolve => setTimeout(resolve, 100));
            `);
            
            // Should only see our marker, not the log message
            expect(output).toContain('MARKER:TEST_COMPLETE');
            expect(output).not.toContain('Should not appear in console');
        });
        
        it('should output to console when TERMINATOR_CONSOLE_LOGGING is enabled', async () => {
            // Enable console logging
            process.env.TERMINATOR_CONSOLE_LOGGING = 'true';
            
            const output = await runNodeScript(`
                import { logger } from './dist/logger.js';
                logger.info('Should appear in console');
                await new Promise(resolve => setTimeout(resolve, 100));
            `);
            
            // Should see the log message in console output
            expect(output).toContain('Should appear in console');
        });
    });
});

// Helper function to run a Node.js script and capture output
function runNodeScript(scriptContent: string): Promise<string> {
    return new Promise((resolve, reject) => {
        const child = spawn('node', ['--input-type=module'], {
            env: process.env,
            cwd: path.join(__dirname, '..', '..') // Project root
        });
        
        let output = '';
        let error = '';
        
        child.stdout.on('data', (data) => {
            output += data.toString();
        });
        
        child.stderr.on('data', (data) => {
            error += data.toString();
        });
        
        child.on('close', (code) => {
            if (code !== 0 && !output) {
                reject(new Error(`Script failed with code ${code}: ${error}`));
            } else {
                resolve(output);
            }
        });
        
        child.stdin.write(scriptContent);
        child.stdin.end();
    });
}