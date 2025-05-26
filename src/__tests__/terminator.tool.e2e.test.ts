/// <reference types="vitest/globals" />
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Mock } from 'vitest';
import { terminatorTool } from '../tool.js';
// Assuming SwiftCLIResult will be exported from types.ts or types.js
// And SdkCallContext will have a logger property.
import type { TerminatorExecuteParams, SdkCallContext, SwiftCLIResult } from '../types.js'; 
import { DEFAULT_LINES } from '../config.js';

// Import the function to be mocked
import { invokeSwiftCLI } from '../swift-cli.js';

// Mock the swift-cli module. The vi.mock call is hoisted.
vi.mock('../swift-cli.js', () => ({
  invokeSwiftCLI: vi.fn(), // This will be the mock function used in tests
}));

// Get a typed reference to the mock. This must be done AFTER vi.mock.
const mockedInvokeSwiftCLI = invokeSwiftCLI as Mock<
    [string[], Record<string, string>, SdkCallContext, number],
    Promise<SwiftCLIResult>
>;

describe('Terminator MCP Tool - End-to-End Parameter Handling', () => {
  let mockContext: SdkCallContext;

  beforeEach(() => {
    // It's good practice to reset mocks before each test if they are reused or modified.
    mockedInvokeSwiftCLI.mockReset(); 
    
    // Define mockContext. Ensure SdkCallContext in types.ts includes this structure.
    mockContext = {
      logger: {
        debug: vi.fn(),
        info: vi.fn(),
        warn: vi.fn(),
        error: vi.fn(),
      },
      // requestMeta: {}, // If SdkCallContext includes other fields like requestMeta
    } as SdkCallContext; // Cast if the imported SdkCallContext type isn't fully aligned yet

    // Default mock implementation for a successful call
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'OK_COMPLETED_FG Mocked CLI output',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });
  });

  it('ExecuteTool_MissingAction_ShouldDefaultToExecuteAndSucceed', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
    };

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    
    expect(result.success).toBe(true);
    expect(result.message).toContain('OK_COMPLETED_FG Mocked CLI output');
    
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('exec'); 
  });

  it('ExecuteTool_ExplicitListAction_ShouldUseProvidedAction', async () => {
    const params: TerminatorExecuteParams = {
      action: 'list',
      project_path: '/Users/steipete/Projects/Terminator',
    };
    
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '[]',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain("Terminator: No active sessions found.");

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('list');
    expect(calledArgs).toContain('--json');
  });

  it('ExecuteTool_InvalidAction_ShouldReturnError', async () => {
    const params = {
      action: 'nonExistentAction',
      project_path: '/Users/steipete/Projects/Terminator',
    } as unknown as TerminatorExecuteParams;

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain("Invalid action 'nonExistentAction'. Must be one of: execute, read, list, info, focus, kill");
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

  it('ExecuteTool_MissingProjectPath_ShouldReturnError', async () => {
    const params = {
      action: 'execute',
      command: 'echo test',
    } as unknown as TerminatorExecuteParams;

    const result = await terminatorTool.handler(params, mockContext);
    
    expect(result.success).toBe(false);
    expect(result.message).toContain("project_path is required");
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

  it('ExecuteTool_StringTrueForBooleanParams_ShouldParseCorrectly', async () => {
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
  
  it('ExecuteTool_StringFalseForBooleanParams_ShouldParseCorrectly', async () => {
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

  it('ExecuteTool_OmittedOptionalBooleansAndNumbers_ShouldUseDefaults', async () => {
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
  
  it('ExecuteTool_EmptyCommandString_ShouldPassNoCommandFlagToSwiftCLI', async () => {
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
  
  it('ExecuteTool_TagProvided_ShouldPassTagToSwiftCLI', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo "hello"',
      tag: 'my-custom-tag'
    };

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('exec');
    expect(calledArgs[1]).toBe('my-custom-tag'); 
  });
  
  it('ListTool_TagProvided_ShouldPassTagOptionToSwiftCLI', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'list',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'filter-by-this-tag'
    };
    
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '[]',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('list');
    expect(calledArgs).toContain('--tag');
    expect(calledArgs).toContain('filter-by-this-tag'); 
  });

  it('ExecuteTool_TimeoutProvidedAsNumber_ShouldPassTimeoutToSwiftCLI', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'sleep 10',
      timeout: 5 
    };
    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--timeout');
    expect(calledArgs).toContain('5');
  });

  it('ExecuteTool_TimeoutProvidedAsString_ShouldParseAndPassTimeoutToSwiftCLI', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'sleep 10',
      timeout: '7' as any 
    };
    await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--timeout');
    expect(calledArgs).toContain('7');
  });

  it('FormatOutput_SuccessfulExecuteBackground_ShouldReturnCorrectMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'sleep 5',
      background: true,
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'OK_SUBMITTED_BG Background process started with PID 12345\nInitial output:\nfoo\nbar',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain('Terminator: Command executed in session');
    expect(result.message).toContain('PID 12345');
    expect(result.message).toContain('Initial output:\nfoo\nbar');
  });

  it('FormatOutput_InfoAction_ShouldReturnFormattedInfo', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'info',
      project_path: '/Users/steipete/Projects/Terminator',
    };
    const mockInfoOutput = {
      version: '1.0.0-alpha.12',
      supportedTerminal: 'iTerm',
      defaultTag: 'terminator_test_project',
      logFilePath: '/path/to/logs/terminator-mcp.log'
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: JSON.stringify(mockInfoOutput),
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain('Terminator v1.0.0-alpha.12');
    expect(result.message).toContain('Sessions: 0');
  });

  it('ErrorHandling_SwiftCLICancelled_ShouldReturnCancelledMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo cancelled'
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      cancelled: true,
      stdout: '',
      stderr: '',
      exitCode: null,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toBe('Terminator action cancelled by request.');
  });

  it('ErrorHandling_SwiftCLIInternalTimeout_ShouldReturnTimeoutMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo timeout'
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      internalTimeoutHit: true,
      stdout: '',
      stderr: '',
      exitCode: null,
      cancelled: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toBe('Terminator Swift CLI unresponsive and was terminated by the wrapper.');
  });

  it('ErrorHandling_SwiftCLIConfigErrorExitCode2_ShouldReturnConfigErrorMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo config_error'
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Bad configuration value for X',
      exitCode: 2,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toContain('Terminator Error (Swift CLI Code 2): Configuration Error: Bad configuration value for X');
  });
  
  it('ErrorHandling_SwiftCLICrashExitCodeNull_ShouldReturnDetailedCrashMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo will_crash'
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Segmentation fault',
      exitCode: null,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toContain('Terminator Error: Swift CLI process terminated unexpectedly');
    expect(result.message).toContain('Check System Settings → Privacy & Security → Automation');
    expect(result.message).toContain('Troubleshooting:');
    expect(result.message).toContain('Swift CLI crashed. This may be due to architecture mismatch or corrupted binary');
  });

  // Additional Test Cases

  it('ReadAction_ValidTag_ShouldCallSwiftCLIWithReadAndTag', async () => {
    const params: TerminatorExecuteParams = {
      action: 'read',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'session-to-read',
      lines: 50,
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'Log line 1\nLog line 2',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain('Log line 1\nLog line 2');

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('read');
    expect(calledArgs[1]).toBe('session-to-read');
    expect(calledArgs).toContain('--lines');
    expect(calledArgs).toContain('50');
  });

  it('ReadAction_DefaultLines_ShouldUseDefaultLines', async () => {
    const params: TerminatorExecuteParams = {
      action: 'read',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'another-session',
      // lines omitted
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'Default output',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    await terminatorTool.handler(params, mockContext);
    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('read');
    expect(calledArgs).toContain('--lines');
    expect(calledArgs).toContain(String(DEFAULT_LINES));
  });

  it('KillAction_ValidTag_ShouldCallSwiftCLIWithKillAndTag', async () => {
    const params: TerminatorExecuteParams = {
      action: 'kill',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'session-to-kill',
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'OK_KILLED Session session-to-kill terminated.',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain('OK_KILLED Session session-to-kill terminated.');

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('kill');
    expect(calledArgs[1]).toBe('session-to-kill');
  });

  it('FocusAction_ValidTag_ShouldCallSwiftCLIWithFocusAndTag', async () => {
    const params: TerminatorExecuteParams = {
      action: 'focus',
      project_path: '/Users/steipete/Projects/Terminator',
      tag: 'session-to-focus',
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'OK_FOCUSED Session session-to-focus is now focused.',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    expect(result.success).toBe(true);
    expect(result.message).toContain('OK_FOCUSED Session session-to-focus is now focused.');

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('focus');
    expect(calledArgs[1]).toBe('session-to-focus');
  });

  it('ExecuteTool_SwiftCLIReturnsSpecificErrorCode_ShouldFormatMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo some_command',
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'A specific error occurred.',
      exitCode: 10, // Example: E_SCRIPT_ERROR from Swift CLI spec
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toContain('Terminator Error (Swift CLI Code 10): A specific error occurred.');
  });

  it('ExecuteTool_SwiftCLIReturnsUnknownErrorCode_ShouldFormatGenericMessage', async () => {
    const params: Partial<TerminatorExecuteParams> = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo another_command',
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'An unknown issue.',
      exitCode: 99, // An exit code not in our known map
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params as TerminatorExecuteParams, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toContain('Terminator Error (Swift CLI Code 99): An unknown issue.');
  });

  it('ExecuteTool_BackgroundFalseAsString_ShouldNotPassBackgroundFlag', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      background: 'false', // Test string 'false'
    };
    await terminatorTool.handler(params, mockContext);
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).not.toContain('--background');
  });

  it('ExecuteTool_FocusNoAsString_ShouldPassNoFocus', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'echo test',
      focus: 'no', // Test string 'no'
    };
    await terminatorTool.handler(params, mockContext);
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain('--focus-mode');
    expect(calledArgs).toContain('no-focus');
  });

  it('ExecuteTool_InvalidProjectPath_ShouldBeCaughtByResolvePathAndFail', async () => {
    // This test relies on resolveEffectiveProjectPath in utils.ts to return an error string
    // We assume the handler passes this error through.
    const params = {
      action: 'execute',
      project_path: '', // Invalid path that resolveEffectiveProjectPath would reject
      command: 'echo test',
    } as TerminatorExecuteParams;

    // We don't need to mock invokeSwiftCLI here as it shouldn't be called.
    const result = await terminatorTool.handler(params, mockContext);

    expect(result.success).toBe(false);
    // The exact message depends on the implementation of resolveEffectiveProjectPath
    expect(result.message).toContain('project_path'); // Check for part of the expected error
    expect(result.message).toContain('project_path is required');
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

  // Newly Added Test Cases
  it('ReadAction_MissingTag_ShouldCallSwiftCLIAndPotentiallyErrorOrReturnDefault', async () => {
    const params: TerminatorExecuteParams = {
      action: 'read',
      project_path: '/Users/steipete/Projects/Terminator',
      // tag is omitted
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: '',
      stderr: 'Error: Tag parameter is required for read action.',
      exitCode: 1, 
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);
    expect(result.success).toBe(false);
    expect(result.message).toContain('Error: Tag parameter is required for read action.');

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const [calledArgs] = mockedInvokeSwiftCLI.mock.calls; // Get the first call's arguments array
    const cliArgs = calledArgs[0]; // The first element of that is the array of CLI string arguments

    expect(cliArgs[0]).toBe('read');
    // Expected args: [action, project_path, --lines, <default_lines_value>, --json]
    // Note: project_path is resolved by the handler and added to Swift CLI args.
    // The exact number of args can vary slightly based on how project_path is handled internally before calling Swift CLI
    // but it should contain these core elements for a read action without a tag.
    expect(cliArgs).not.toContain('--tag');
    expect(cliArgs).toContain('--lines');
    expect(cliArgs).toContain(String(DEFAULT_LINES));
    expect(cliArgs).toContain('--json'); // list, info, read actions should include --json
  });

  it('ExecuteTool_BackgroundTrueWithExplicitTimeout_ShouldPassBothToSwiftCLI', async () => {
    const params: TerminatorExecuteParams = {
      action: 'execute',
      project_path: '/Users/steipete/Projects/Terminator',
      command: 'long_running_script.sh',
      background: true,
      timeout: 300,
    };
    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: 'OK_SUBMITTED_BG Background process started with PID 67890',
      stderr: '',
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    await terminatorTool.handler(params, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe('exec');
    expect(calledArgs).toContain('--background');
    expect(calledArgs).toContain('--timeout');
    expect(calledArgs).toContain('300');
  });

  it('ExecuteTool_InvalidProjectPathWithCommand_ShouldStillFailOnPathResolution', async () => {
    const params = {
      action: 'execute',
      project_path: null as any, 
      command: 'echo "This command should not run"',
    } as TerminatorExecuteParams;

    const result = await terminatorTool.handler(params, mockContext);

    expect(result.success).toBe(false);
    expect(result.message).toContain("project_path is required");
    expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
  });

}); 