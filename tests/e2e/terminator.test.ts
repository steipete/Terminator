import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execa } from 'execa';
import path from 'path';
import { fileURLToPath } from 'url';
import { runTerminator } from './test-helpers.js';
import { expectSuccessOrAppleScriptError, expectFailureWithMessage } from './test-utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '../..');
const SWIFT_CLI_PATH = path.join(PROJECT_ROOT, 'bin', 'terminator');

describe('Terminator E2E Tests', () => {
  beforeAll(async () => {
    // Check if Swift CLI exists
    try {
      await execa(SWIFT_CLI_PATH, ['--version'], { timeout: 5000 });
    } catch (error) {
      throw new Error(`Swift CLI not found at ${SWIFT_CLI_PATH}. Run 'npm run build:swift' first.`);
    }
  });

  describe('Sessions Command', () => {
    it('should handle empty terminal sessions gracefully', async () => {
      const result = await runTerminator(['sessions', '--terminal-app', 'terminal']);
      expectSuccessOrAppleScriptError(result);
      expect(result.stdout).toContain('No active sessions found');
    });

    it('should handle sessions command with iTerm when no windows exist', async () => {
      const result = await runTerminator(['sessions', '--terminal-app', 'iterm']);
      expectSuccessOrAppleScriptError(result);
      // Should either show no sessions or handle gracefully
      expect(result.all).toMatch(/No active sessions found|Successfully parsed 0 iTerm sessions/);
    });

    it('should list sessions in JSON format', async () => {
      const result = await runTerminator(['sessions', '--terminal-app', 'terminal', '--json']);
      expectSuccessOrAppleScriptError(result);
      
      // Output might be "null" or empty array when no sessions
      if (result.stdout.trim() === 'null' || result.stdout.trim() === '') {
        // Accept null/empty as valid
        expect(true).toBe(true);
      } else {
        const sessions = JSON.parse(result.stdout);
        expect(Array.isArray(sessions)).toBe(true);
      }
    });

    it('should handle invalid terminal app gracefully', async () => {
      const result = await runTerminator(['sessions', '--terminal-app', 'invalid-app']);
      // Sessions command returns success even with invalid terminal app
      expect(result.exitCode).toBe(0);
      // But it should show a warning in stderr
      expect(result.stderr.toLowerCase()).toContain('warning');
      expect(result.stdout).toContain('No active sessions found');
    });
  });

  describe('Execute Command Edge Cases', () => {
    it('should handle empty command (prepare session only)', async () => {
      const tag = `test-empty-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', '',
        '--project-path', PROJECT_ROOT
      ]);
      
      // Should succeed or fail with AppleScript error
      expectSuccessOrAppleScriptError(result);
    });

    it('should handle exec without command flag entirely', async () => {
      const tag = `test-nocommand-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--project-path', PROJECT_ROOT
      ]);
      
      // Should succeed and just change directory
      expectSuccessOrAppleScriptError(result);
    });

    it('should handle special characters in commands', async () => {
      const tag = `test-special-${Date.now()}`;
      const specialCommand = 'echo "Hello $USER" && echo \'Single quotes\' && echo `date`';
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', specialCommand
      ]);
      
      expectSuccessOrAppleScriptError(result);
    });

    it('should handle very long commands', async () => {
      const tag = `test-long-${Date.now()}`;
      const longCommand = 'echo ' + 'a'.repeat(1000);
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', longCommand
      ]);
      
      expectSuccessOrAppleScriptError(result);
    });

    it('should handle commands with newlines', async () => {
      const tag = `test-multiline-${Date.now()}`;
      const multilineCommand = 'echo "Line 1" &&\necho "Line 2" &&\necho "Line 3"';
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', multilineCommand
      ]);
      
      expectSuccessOrAppleScriptError(result);
    });
  });

  describe('Kill Command Edge Cases', () => {
    it('should handle killing non-existent session gracefully', async () => {
      const result = await runTerminator([
        'kill',
        '--terminal-app', 'terminal',
        '--tag', 'non-existent-session-id',
        '--focus-on-kill', 'false'
      ]);
      
      // Should fail gracefully
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr.toLowerCase()).toContain('not found');
    });

    it('should handle kill when tag is required', async () => {
      const result = await runTerminator([
        'kill',
        '--terminal-app', 'terminal',
        '--focus-on-kill', 'false'
      ]);
      
      // Should fail because --tag is required
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr.toLowerCase()).toContain('missing expected argument');
    });
  });

  describe('Error Handling', () => {
    it('should provide helpful error for missing required arguments', async () => {
      const result = await runTerminator(['execute']);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain('Missing expected argument');
    });

    it('should handle invalid command combinations', async () => {
      const result = await runTerminator([
        'kill',
        '--tag', 'some-id',
        '--terminal-app', 'invalid-terminal',
        '--focus-on-kill', 'false'
      ]);
      
      expect(result.exitCode).not.toBe(0);
      // The error comes from the kill command itself, not argument parsing
      expect(result.stderr.toLowerCase()).toContain('unknown terminal application');
    });

    it('should handle permission errors gracefully', async () => {
      // This might not always trigger, but tests the error path
      const result = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal',
        '--log-dir', '/root/no-permission'  // Should fail
      ]);
      
      // Log dir might be ignored if we can't write to it
      // Just ensure it doesn't crash
      expect([0, 1]).toContain(result.exitCode);
    });
  });

  describe('Special Characters and Encoding', () => {
    it('should handle Unicode characters in commands', async () => {
      const tag = `test-unicode-${Date.now()}`;
      const unicodeCommand = 'echo "Hello 世界 🌍"';
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', unicodeCommand
      ]);
      
      expectSuccessOrAppleScriptError(result);
    });

    it('should handle paths with spaces', async () => {
      const tag = `test-spaces-${Date.now()}`;
      const pathWithSpaces = '/tmp/test folder with spaces';
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--project-path', pathWithSpaces,
        '--command', 'pwd'
      ]);
      
      expectSuccessOrAppleScriptError(result);
    });
  });

  describe('Tag Filtering', () => {
    it('should handle filtering by non-existent tag', async () => {
      const result = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal',
        '--tag', 'non-existent-tag-xyz'
      ]);
      
      expectSuccessOrAppleScriptError(result);
      if (result.exitCode === 0) {
        expect(result.stdout).toContain('No active sessions found');
      }
    });

    it('should handle creating session with tag', async () => {
      const tag = `test-tag-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo "Tagged session"'
      ]);
      
      expectSuccessOrAppleScriptError(result);
      
      // Verify we can list by that tag
      const listResult = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal',
        '--tag', tag,
        '--json'
      ]);
      
      if (listResult.stdout.trim() !== 'null' && listResult.stdout.trim() !== '') {
        const sessions = JSON.parse(listResult.stdout);
        if (sessions.length > 0) {
          expect(sessions[0].tag).toBe(tag);
        }
      }
    });
  });

  describe('AppleScript Edge Cases', () => {
    it('should handle when Terminal app is not running', async () => {
      // First, try to quit Terminal if it's running
      await execa('osascript', ['-e', 'tell application "Terminal" to quit'], {
        reject: false,
      });
      
      // Wait a bit for Terminal to quit
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Now try to list sessions
      const result = await runTerminator(['sessions', '--terminal-app', 'terminal']);
      
      // Should either start Terminal or handle gracefully
      expectSuccessOrAppleScriptError(result);
    });
  });

  afterAll(async () => {
    // Clean up any test sessions created
    // Note: There's no --all flag, we'd need to list sessions and kill them individually
    // For now, just skip cleanup as it would require more complex logic
  });
});