// Test utilities for Terminator E2E tests

export function expectSuccessOrAppleScriptError(result: { exitCode: number | null, stderr: string }) {
  if (result.exitCode === 0) {
    // Success - automation worked
    return;
  }
  
  if (result.exitCode === 3) {
    // AppleScript error - automation not available
    expect(result.stderr.toLowerCase()).toMatch(/applescript|automation|permission/);
    return;
  }
  
  // Unexpected error
  throw new Error(`Expected success (0) or AppleScript error (3), got exit code ${result.exitCode}: ${result.stderr}`);
}

export function expectFailureWithMessage(result: { exitCode: number | null, stderr: string }, message: string) {
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr.toLowerCase()).toContain(message.toLowerCase());
}