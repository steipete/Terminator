/// <reference types="vitest/globals" />
import { describe, it, expect, beforeEach } from 'vitest';
import { terminatorTool } from '../tool.js';
import type { TerminatorExecuteParams } from '../types.js';
import { DEFAULT_LINES } from '../config.js';
import { mockedInvokeSwiftCLI, createMockContext, mockResponses } from './e2e-test-setup.js';
import type { SdkCallContext } from '../types.js';

describe('Terminator MCP Tool - Execute Action E2E Tests', () => {
  let mockContext: SdkCallContext;

  beforeEach(() => {
    mockedInvokeSwiftCLI.mockReset();
    mockContext = createMockContext();
    mockedInvokeSwiftCLI.mockResolvedValue(mockResponses.successfulExecution);
  });

  it('should default to execute action when action is missing', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(result.success).toBe(true);
    expect(result.message).toContain('OK_COMPLETED_FG Mocked CLI output');
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('execute'); 
  });

  it('should return error when project_path is missing', async () => {
    const params = {
      action: 'execute',
      command: 'echo test',
    } as unknown as TerminatorExecuteParams;

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain("project_path is required");
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

  it('should parse string "true" for boolean parameters correctly', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      background: 'true' as any,
      focus: 'yes' as any,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--background');
    expect(calledArgs).toContain('--focus-mode');
    expect(calledArgs).toContain('force-focus');
  });

  it('should parse string "false" for boolean parameters correctly', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      background: 'false' as any, 
      focus: 'no' as any,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).not.toContain('--background');
    expect(calledArgs).toContain('--focus-mode');
    expect(calledArgs).toContain('no-focus'); 
  });

  it('should use defaults when optional booleans and numbers are omitted', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    
    expect(calledArgs).not.toContain('--background');
    expect(calledArgs).toContain('--focus-mode');
    expect(calledArgs).toContain('force-focus');
    expect(calledArgs).toContain('--lines');
    expect(calledArgs).toContain(String(DEFAULT_LINES));
    expect(calledArgs).not.toContain('--timeout');
  });

  it('should not pass command flag when command string is empty', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: '',
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).not.toContain('--command');
  });

  it('should pass tag to Swift CLI when provided', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo "hello"',
      tag: 'my-custom-tag'
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--tag');
    expect(calledArgs).toContain('my-custom-tag');
  });

  it('should pass timeout as number to Swift CLI', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      timeout: 30,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--timeout');
    expect(calledArgs).toContain('30');
  });

  it('should parse and pass timeout as string to Swift CLI', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      timeout: '45' as any,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--timeout');
    expect(calledArgs).toContain('45');
  });

  it('should not pass background flag when background is "false" string', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      background: 'false' as any,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).not.toContain('--background');
  });

  it('should pass no-focus when focus is "no" string', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute', 
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      focus: 'no' as any,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--focus-mode');
    expect(calledArgs).toContain('no-focus');
  });

  it('should fail on invalid project path resolution', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/../../invalid/../path',
      command: 'echo test',
    };

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain("Invalid project path");
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

  it('should pass both background and timeout when provided', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'npm run dev',
      background: true,
      timeout: 120,
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--background');
    expect(calledArgs).toContain('--timeout');
    expect(calledArgs).toContain('120');
  });

  it('should fail on invalid project path even with valid command', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '../../../etc/passwd',
      command: 'echo "valid command"',
    };

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain("Invalid project path");
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

  it('should return formatted message for successful background execution', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'npm run dev',
      background: true,
    };

    mockedInvokeSwiftCLI.mockResolvedValue(mockResponses.successfulBackgroundExecution);

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(result.success).toBe(true);
    expect(result.message).toContain('OK_STARTED_BG Command started in background');
  });
});