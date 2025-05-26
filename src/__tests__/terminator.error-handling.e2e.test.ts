/// <reference types="vitest/globals" />
import { describe, it, expect, beforeEach } from 'vitest';
import { terminatorTool } from '../tool.js';
import type { TerminatorExecuteParams } from '../types.js';
import { mockedInvokeSwiftCLI, createMockContext, mockResponses } from './e2e-test-setup.js';
import type { SdkCallContext } from '../types.js';

describe('Terminator MCP Tool - Error Handling E2E Tests', () => {
  let mockContext: SdkCallContext;

  beforeEach(() => {
    mockedInvokeSwiftCLI.mockReset();
    mockContext = createMockContext();
  });

  it('should return cancelled message when Swift CLI is cancelled', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'long-running-command',
    };

    mockedInvokeSwiftCLI.mockResolvedValue(mockResponses.cancelled);

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Operation was cancelled');
  });

  it('should return timeout message when Swift CLI times out', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'slow-command',
    };

    mockedInvokeSwiftCLI.mockResolvedValue(mockResponses.timeout);

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Operation timed out');
  });

  it('should return config error message for exit code 2', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    mockedInvokeSwiftCLI.mockResolvedValue(mockResponses.configError);

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Configuration error');
  });

  it('should return detailed crash message when exit code is null', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'Some partial output',
      stderr: 'Segmentation fault',
      exitCode: null,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Swift CLI process crashed');
    expect(result.message).toContain('Segmentation fault');
  });

  it('should format message for specific error code', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Terminal app not supported',
      exitCode: 3, // TERMINAL_NOT_SUPPORTED
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Terminal app not supported');
  });

  it('should format generic message for unknown error code', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Unknown error occurred',
      exitCode: 99,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Swift CLI failed with exit code 99');
    expect(result.message).toContain('Unknown error occurred');
  });

  it('should handle session not found error', async () => {
    const params: TerminatorExecuteParams = {
      action: 'read',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'non-existent-session',
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Session with tag "non-existent-session" not found',
      exitCode: 11, // SESSION_NOT_FOUND
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Session not found');
  });

  it('should handle process termination error', async () => {
    const params: TerminatorExecuteParams = {
      action: 'kill',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'protected-session',
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Failed to terminate process',
      exitCode: 12, // PROCESS_TERMINATION_FAILED
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Failed to terminate process');
  });

  it('should handle invalid window index error', async () => {
    const params: TerminatorExecuteParams = {
      action: 'focus',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'bad-window-session',
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Invalid window index',
      exitCode: 7, // INVALID_WINDOW_INDEX
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain('Invalid window or tab');
  });
});