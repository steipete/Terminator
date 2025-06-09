/// <reference types="vitest/globals" />
import { describe, it, expect, beforeEach } from 'vitest';
import { terminatorTool } from '../tool.js';
import type { TerminatorExecuteParams } from '../types.js';
import { mockedInvokeSwiftCLI, createMockContext, mockResponses } from './e2e-test-setup.js';
import type { SdkCallContext } from '../types.js';

describe('Terminator MCP Tool - List Action E2E Tests', () => {
  let mockContext: SdkCallContext;

  beforeEach(() => {
    mockedInvokeSwiftCLI.mockReset();
    mockContext = createMockContext();
  });

  it('should use provided list action explicitly', async () => {
    const params: TerminatorExecuteParams = {
      action: 'sessions',
      project_path: '/Users/steipete/Projects/Terminator',
    };
    
    mockedInvokeSwiftCLI.mockResolvedValue(mockResponses.emptyList);

    const result = await terminatorTool.handler(params, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain("Terminator: No active sessions found.");

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('sessions');
    expect(calledArgs).toContain('--json');
  });

  it('should pass tag option to Swift CLI when provided', async () => {
    const params: TerminatorExecuteParams = {
      action: 'sessions',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'specific-tag',
    };
    
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '[{"tag": "specific-tag", "pid": 1234, "command": "echo test"}]',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(true);
    expect(result.message).toContain("specific-tag");
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('sessions');
    expect(calledArgs).toContain('--tag');
    expect(calledArgs).toContain('specific-tag');
    expect(calledArgs).toContain('--json');
  });

  it('should handle list with multiple sessions', async () => {
    const params: TerminatorExecuteParams = {
      action: 'sessions',
      project_path: '/Users/steipete/Projects/Terminator',
    };
    
    const mockSessions = [
      { tag: 'session-1', pid: 1234, command: 'npm run dev' },
      { tag: 'session-2', pid: 5678, command: 'python server.py' }
    ];
    
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: JSON.stringify(mockSessions),
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(true);
    expect(result.message).toContain("session-1");
    expect(result.message).toContain("session-2");
    expect(result.message).toContain("npm run dev");
    expect(result.message).toContain("python server.py");
  });

  it('should handle malformed JSON response gracefully', async () => {
    const params: TerminatorExecuteParams = {
      action: 'sessions',
      project_path: '/Users/steipete/Projects/Terminator',
    };
    
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'Not valid JSON',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain("Failed to parse session list");
  });
});