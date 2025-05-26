/// <reference types="vitest/globals" />
import { vi } from 'vitest';
import type { Mock } from 'vitest';
import type { SdkCallContext, SwiftCLIResult } from '../types.js';
import { invokeSwiftCLI } from '../swift-cli.js';

// Mock the swift-cli module
vi.mock('../swift-cli.js', () => ({
  invokeSwiftCLI: vi.fn(),
}));

// Get a typed reference to the mock
export const mockedInvokeSwiftCLI = invokeSwiftCLI as Mock<
  [string[], Record<string, string>, SdkCallContext, number],
  Promise<SwiftCLIResult>
>;

// Create a standard mock context
export function createMockContext(): SdkCallContext {
  return {
    logger: {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    },
  } as SdkCallContext;
}

// Common mock responses
export const mockResponses = {
  successfulExecution: {
    stdout: 'OK_COMPLETED_FG Mocked CLI output',
    stderr: '',
    exitCode: 0,
    cancelled: false,
    internalTimeoutHit: false,
  },
  successfulBackgroundExecution: {
    stdout: 'OK_STARTED_BG Command started in background',
    stderr: '',
    exitCode: 0,
    cancelled: false,
    internalTimeoutHit: false,
  },
  emptyList: {
    stdout: '[]',
    stderr: '',
    exitCode: 0,
    cancelled: false,
    internalTimeoutHit: false,
  },
  cancelled: {
    stdout: '',
    stderr: '',
    exitCode: null,
    cancelled: true,
    internalTimeoutHit: false,
  },
  timeout: {
    stdout: '',
    stderr: '',
    exitCode: null,
    cancelled: false,
    internalTimeoutHit: true,
  },
  configError: {
    stdout: '',
    stderr: 'Configuration error',
    exitCode: 2,
    cancelled: false,
    internalTimeoutHit: false,
  },
};