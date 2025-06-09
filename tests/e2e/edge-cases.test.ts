import { describe, it, expect, beforeAll } from 'vitest';
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

describe('Terminator Edge Cases', () => {
  beforeAll(async () => {
    // Check if Swift CLI exists
    try {
      await execa(SWIFT_CLI_PATH, ['--version'], { timeout: 5000 });
    } catch (error) {
      throw new Error(`Swift CLI not found at ${SWIFT_CLI_PATH}. Run 'npm run build:swift' first.`);
    }
  });

  describe('Range Bounds Edge Cases', () => {
    it('should handle empty AppleScript lists without crashing', async () => {
      // This specifically tests the Range bounds fix
      const result = await runTerminator(['sessions', '--terminal-app', 'terminal']);
      
      // Should not crash with Range bounds error
      expect(result.exitCode).toBe(0);
      expect(result.stderr).not.toContain('Range requires lowerBound <= upperBound');
      expect(result.stderr).not.toContain('Fatal error');
    });

    it('should handle nested empty lists in AppleScript results', async () => {
      // Test with iTerm which might return nested structures
      const result = await runTerminator(['sessions', '--terminal-app', 'iterm', '--json']);
      
      expect(result.exitCode).toBe(0);
      expect(result.stderr).not.toContain('Range requires lowerBound <= upperBound');
      
      // Handle null or empty JSON response
      if (result.stdout.trim() === 'null' || result.stdout.trim() === '') {
        expect(true).toBe(true);
      } else {
        const sessions = JSON.parse(result.stdout);
        expect(Array.isArray(sessions)).toBe(true);
      }
    });
  });

  describe('Command Escaping and Special Cases', () => {
    it('should handle commands with backticks', async () => {
      const tag = `test-backticks-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo `whoami`'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle commands with dollar signs', async () => {
      const tag = `test-dollar-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo $HOME'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle commands with semicolons', async () => {
      const tag = `test-semicolon-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo "First"; echo "Second"'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle commands with pipes', async () => {
      const tag = `test-pipe-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo "test" | cat'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle commands with redirects', async () => {
      const tag = `test-redirect-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'echo "test" > /tmp/terminator-test.txt'
      ]);
      
      expect(result.exitCode).toBe(0);
    });
  });

  describe('Path Edge Cases', () => {
    it('should handle paths with tildes', async () => {
      const tag = `test-tilde-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--project-path', '~/Desktop',
        '--command', 'pwd'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle paths with environment variables', async () => {
      const tag = `test-envvar-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--project-path', '$HOME/Desktop',
        '--command', 'pwd'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle relative paths', async () => {
      const tag = `test-relative-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--project-path', '.',
        '--command', 'pwd'
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle non-existent paths gracefully', async () => {
      const tag = `test-nonexist-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--project-path', '/this/path/does/not/exist/xyz123',
        '--command', 'pwd'
      ]);
      
      // Should still create session but cd might fail
      expect(result.exitCode).toBe(0);
    });
  });

  describe('Null and Undefined Handling', () => {
    it('should handle completely empty exec command', async () => {
      const tag = `test-empty-exec-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal'
      ]);
      
      // Should create a new session without executing any command
      expect(result.exitCode).toBe(0);
    });

    it('should handle whitespace-only commands', async () => {
      const tag = `test-whitespace-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', '   '
      ]);
      
      expect(result.exitCode).toBe(0);
    });

    it('should handle zero-length command string', async () => {
      const tag = `test-zerolen-${Date.now()}`;
      const result = await runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', ''
      ]);
      
      expect(result.exitCode).toBe(0);
    });
  });

  describe('Concurrent Operations', () => {
    it('should handle multiple exec commands in quick succession', async () => {
      const promises = [];
      
      for (let i = 0; i < 5; i++) {
        const tag = `test-concurrent-${Date.now()}-${i}`;
        promises.push(runTerminator([
          'execute',
          tag,
          '--terminal-app', 'terminal',
          '--command', `echo "Concurrent test ${i}"`
        ]));
      }
      
      const results = await Promise.all(promises);
      
      // All should succeed
      results.forEach(result => {
        expect(result.exitCode).toBe(0);
      });
    });

    it('should handle sessions while sessions are being created', async () => {
      const tag = `test-concurrent-sessions-${Date.now()}`;
      // Start creating a session
      const execPromise = runTerminator([
        'execute',
        tag,
        '--terminal-app', 'terminal',
        '--command', 'sleep 5'
      ]);
      
      // Immediately query sessions
      const listResult = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal'
      ]);
      
      expect(listResult.exitCode).toBe(0);
      
      // Wait for exec to complete
      const execResult = await execPromise;
      expect(execResult.exitCode).toBe(0);
    });
  });

  describe('Session ID Edge Cases', () => {
    it('should handle very long session IDs', async () => {
      const longId = 'a'.repeat(500);
      const result = await runTerminator([
        'kill',
        '--terminal-app', 'terminal',
        '--session-id', longId
      ]);
      
      // Should fail gracefully
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr.toLowerCase()).toContain('not found');
    });

    it('should handle session IDs with special characters', async () => {
      const specialId = 'session-!@#$%^&*()_+{}|:"<>?';
      const result = await runTerminator([
        'kill',
        '--terminal-app', 'terminal',
        '--session-id', specialId
      ]);
      
      // Should fail gracefully
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr.toLowerCase()).toContain('not found');
    });
  });

  describe('Logging Edge Cases', () => {
    it('should handle invalid log directory gracefully', async () => {
      const result = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal',
        '--log-dir', '/dev/null/not-a-directory'
      ]);
      
      // Should work but might not write logs
      expect([0, 1]).toContain(result.exitCode);
    });

    it('should handle very verbose logging', async () => {
      const result = await runTerminator([
        'sessions',
        '--terminal-app', 'terminal',
        '--log-level', 'debug',
        '--verbose'
      ]);
      
      expect(result.exitCode).toBe(0);
      // Should have debug output
      expect(result.all).toContain('DEBUG');
    });
  });
});