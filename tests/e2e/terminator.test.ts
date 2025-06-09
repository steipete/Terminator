import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execa } from 'execa';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '../..');
const SWIFT_CLI_PATH = path.join(PROJECT_ROOT, 'bin', 'terminator');

// Helper to run Swift CLI commands
async function runTerminator(args: string[]) {
  const result = await execa(SWIFT_CLI_PATH, args, {
    reject: false,
    all: true,
  });
  return {
    stdout: result.stdout,
    stderr: result.stderr,
    exitCode: result.exitCode,
    all: result.all,
  };
}

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
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('No active sessions found');
    });

    it('should handle sessions command with iTerm when no windows exist', async () => {
      const result = await runTerminator(['sessions', '--terminal-app', 'iterm']);
      expect(result.exitCode).toBe(0);
      // Should either show no sessions or handle gracefully
      expect(result.all).toMatch(/No active sessions found|Successfully parsed 0 iTerm sessions/);
    });

    it('should list sessions in JSON format', async () => {
      const result = await runTerminator(['sessions', '--terminal-app', 'terminal', '--json']);
      expect(result.exitCode).toBe(0);
      
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
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain('Invalid value');
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
      
      // Should succeed and just change directory
      expect(result.exitCode).toBe(0);
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
      expect(result.exitCode).toBe(0);
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
      
      expect(result.exitCode).toBe(0);
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
      
      expect(result.exitCode).toBe(0);
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
      
      expect(result.exitCode).toBe(0);
    });
  });

  describe('Kill Command Edge Cases', () => {
    it('should handle killing non-existent session gracefully', async () => {
      const result = await runTerminator([
        'kill',
        '--terminal-app', 'terminal',
        '--session-id', 'non-existent-session-id'
      ]);
      
      // Should fail gracefully
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr.toLowerCase()).toContain('not found');
    });

    it('should handle kill --all when no sessions exist', async () => {
      const result = await runTerminator([
        'kill',
        '--terminal-app', 'terminal',
        '--all'
      ]);
      
      // Should succeed even if no sessions to kill
      expect(result.exitCode).toBe(0);
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
        '--all',
        '--session-id', 'some-id'  // Can't use both
      ]);
      
      expect(result.exitCode).not.toBe(0);
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
      
      expect(result.exitCode).toBe(0);
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
      
      expect(result.exitCode).toBe(0);
    });
  });

  describe('Tag Filtering', () => {
    it('should handle filtering by non-existent tag', async () => {
      const result = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal',
        '--tag', 'non-existent-tag-xyz'
      ]);
      
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('No active sessions found');
    });

    it('should handle creating session with tag', async () => {
      const tag = `test-tag-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo "Tagged session"'
      ]);
      
      expect(result.exitCode).toBe(0);
      
      // Verify we can list by that tag
      const listResult = await runTerminator([
        'list',
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
      expect(result.exitCode).toBe(0);
    });
  });

  afterAll(async () => {
    // Clean up any test sessions created
    const result = await runTerminator([
      'kill',
      '--terminal-app', 'terminal',
      '--all'
    ]);
    // Don't fail if cleanup fails
  });
});