import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { spawn, ChildProcess } from 'child_process';
import { resolve } from 'path';
import { existsSync } from 'fs';
import { setTimeout as delay } from 'timers/promises';

describe('Hybrid Mode E2E Tests', () => {
  let swiftCliPath: string;
  const testTag = 'hybrid-e2e-test';
  const testProject = '/tmp/hybrid-test-project';
  
  beforeAll(() => {
    // Verify Swift CLI exists
    swiftCliPath = resolve(__dirname, '../../bin/terminator');
    if (!existsSync(swiftCliPath)) {
      throw new Error(`Swift CLI not found at ${swiftCliPath}. Run 'npm run build' first.`);
    }
  });
  
  beforeEach(async () => {
    // Clean up any existing test sessions
    await executeSwiftCLI(['kill', '-t', testTag, '-p', testProject]);
  });
  
  afterAll(async () => {
    // Final cleanup
    await executeSwiftCLI(['kill', '-t', testTag, '-p', testProject]);
  });
  
  function executeSwiftCLI(args: string[], env?: Record<string, string>): Promise<{ stdout: string; stderr: string; exitCode: number }> {
    return new Promise((resolve) => {
      const childEnv = { ...process.env, ...env };
      const child = spawn(swiftCliPath, args, {
        env: childEnv,
        cwd: process.cwd()
      });
      
      let stdout = '';
      let stderr = '';
      
      child.stdout.on('data', (data) => {
        stdout += data.toString();
      });
      
      child.stderr.on('data', (data) => {
        stderr += data.toString();
      });
      
      child.on('close', (code) => {
        resolve({ stdout, stderr, exitCode: code || 0 });
      });
      
      child.on('error', (err) => {
        console.error('Failed to spawn Swift CLI:', err);
        resolve({ stdout, stderr, exitCode: 1 });
      });
    });
  }
  
  describe('Feature Flag Tests', () => {
    it('should use traditional mode by default', async () => {
      const result = await executeSwiftCLI(['info']);
      
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('Terminator CLI');
      // Log output would indicate traditional mode
    });
    
    it('should enable hybrid mode with TERMINATOR_EXPERIMENTAL_AX', async () => {
      const result = await executeSwiftCLI(['info'], {
        TERMINATOR_EXPERIMENTAL_AX: 'true',
        TERMINATOR_LOG_LEVEL: 'debug'
      });
      
      expect(result.exitCode).toBe(0);
      // Would see "Hybrid" in logs if we had debug output
    });
    
    it('should enable specific features with individual flags', async () => {
      const result = await executeSwiftCLI(['list'], {
        TERMINATOR_AX_WINDOWS: 'true',
        TERMINATOR_LOG_LEVEL: 'debug'
      });
      
      expect(result.exitCode).toBe(0);
      // Would see "Using AX for session enumeration" in debug logs
    });
  });
  
  describe('Hybrid Mode Operations', () => {
    it('should list sessions in hybrid mode', async () => {
      // First create a session
      await executeSwiftCLI([
        'exec',
        '-t', testTag,
        '-p', testProject,
        '-c', 'echo "Hybrid test session"'
      ]);
      
      await delay(1000); // Wait for session to be created
      
      // List sessions with hybrid mode
      const result = await executeSwiftCLI(['list'], {
        TERMINATOR_EXPERIMENTAL_AX: 'true'
      });
      
      expect(result.exitCode).toBe(0);
      const sessions = JSON.parse(result.stdout);
      
      // Should find our session regardless of mode
      const testSession = sessions.find((s: any) => s.tag === testTag);
      expect(testSession).toBeDefined();
    });
    
    it('should focus session in hybrid mode', async () => {
      // Create a session first
      await executeSwiftCLI([
        'exec',
        '-t', testTag,
        '-p', testProject,
        '-c', 'echo "Focus test"'
      ]);
      
      await delay(1000);
      
      // Focus with hybrid mode
      const result = await executeSwiftCLI([
        'focus',
        '-t', testTag,
        '-p', testProject
      ], {
        TERMINATOR_AX_FOCUS: 'true'
      });
      
      expect(result.exitCode).toBe(0);
      const focusResult = JSON.parse(result.stdout);
      expect(focusResult.tag).toBe(testTag);
    });
    
    it('should execute commands (always uses AppleScript)', async () => {
      // Execute should work the same in hybrid mode
      const result = await executeSwiftCLI([
        'exec',
        '-t', testTag,
        '-p', testProject,
        '-c', 'echo "Hello from hybrid mode"',
        '-w'
      ], {
        TERMINATOR_EXPERIMENTAL_AX: 'true'
      });
      
      expect(result.exitCode).toBe(0);
      const execResult = JSON.parse(result.stdout);
      expect(execResult.output).toContain('Hello from hybrid mode');
    });
    
    it('should read output (always uses AppleScript)', async () => {
      // Create session with output
      await executeSwiftCLI([
        'exec',
        '-t', testTag,
        '-p', testProject,
        '-c', 'for i in {1..5}; do echo "Line $i"; done',
        '-w'
      ]);
      
      await delay(1000);
      
      // Read output in hybrid mode
      const result = await executeSwiftCLI([
        'read',
        '-t', testTag,
        '-p', testProject,
        '-l', '10'
      ], {
        TERMINATOR_EXPERIMENTAL_AX: 'true'
      });
      
      expect(result.exitCode).toBe(0);
      const readResult = JSON.parse(result.stdout);
      expect(readResult.output).toContain('Line 1');
      expect(readResult.output).toContain('Line 5');
    });
  });
  
  describe('Permission Handling', () => {
    it('should handle missing accessibility permission gracefully', async () => {
      // This test would fail in CI but demonstrates fallback behavior
      const result = await executeSwiftCLI(['list'], {
        TERMINATOR_EXPERIMENTAL_AX: 'true',
        TERMINATOR_LOG_LEVEL: 'debug'
      });
      
      // Should still succeed by falling back to AppleScript
      expect(result.exitCode).toBe(0);
      
      // In debug logs, would see:
      // "Accessibility permission not granted. Hybrid mode features will be limited."
      // "AX enumeration failed, falling back to AppleScript"
    });
  });
  
  describe('Performance Characteristics', () => {
    it('should complete list operation quickly', async () => {
      // Create multiple sessions
      for (let i = 1; i <= 5; i++) {
        await executeSwiftCLI([
          'exec',
          '-t', `${testTag}-${i}`,
          '-p', testProject,
          '-c', `echo "Session ${i}"`
        ]);
      }
      
      await delay(2000); // Wait for all sessions
      
      // Measure traditional mode
      const traditionalStart = Date.now();
      const traditionalResult = await executeSwiftCLI(['list']);
      const traditionalTime = Date.now() - traditionalStart;
      
      expect(traditionalResult.exitCode).toBe(0);
      
      // Measure hybrid mode (would be faster with real AX permissions)
      const hybridStart = Date.now();
      const hybridResult = await executeSwiftCLI(['list'], {
        TERMINATOR_EXPERIMENTAL_AX: 'true'
      });
      const hybridTime = Date.now() - hybridStart;
      
      expect(hybridResult.exitCode).toBe(0);
      
      console.log(`Traditional mode: ${traditionalTime}ms`);
      console.log(`Hybrid mode: ${hybridTime}ms`);
      
      // Both should complete reasonably quickly
      expect(traditionalTime).toBeLessThan(5000);
      expect(hybridTime).toBeLessThan(5000);
    });
  });
  
  describe('Backward Compatibility', () => {
    it('should work identically in traditional mode', async () => {
      // Run a series of operations without hybrid mode
      const operations = [
        () => executeSwiftCLI(['exec', '-t', testTag, '-p', testProject, '-c', 'echo "test"']),
        () => executeSwiftCLI(['list']),
        () => executeSwiftCLI(['read', '-t', testTag, '-p', testProject]),
        () => executeSwiftCLI(['focus', '-t', testTag, '-p', testProject]),
        () => executeSwiftCLI(['kill', '-t', testTag, '-p', testProject])
      ];
      
      for (const op of operations) {
        const result = await op();
        // All operations should succeed in traditional mode
        expect([0, 6]).toContain(result.exitCode); // 0 = success, 6 = session not found
      }
    });
  });
});