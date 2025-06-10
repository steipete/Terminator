/// <reference types="vitest/globals" />
import { describe, it, expect, beforeEach } from "vitest";
import { terminatorTool } from "../tool.js";
import type { TerminatorExecuteParams } from "../types.js";
import { DEFAULT_LINES } from "../config.js";
import { mockedInvokeSwiftCLI, createMockContext } from "./e2e-test-setup.js";
import type { SdkCallContext } from "../types.js";

describe("Terminator MCP Tool - Read Action E2E Tests", () => {
  let mockContext: SdkCallContext;

  beforeEach(() => {
    mockedInvokeSwiftCLI.mockReset();
    mockContext = createMockContext();
  });

  it("should call Swift CLI with read action and tag when valid tag provided", async () => {
    const params: TerminatorExecuteParams = {
      action: "read",
      project_path: "/Users/steipete/Projects/Terminator",
      tag: "my-session-tag",
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: "Session output content here",
      stderr: "",
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);

    expect(result.success).toBe(true);
    expect(result.message).toContain("Session output content here");

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe("read");
    expect(calledArgs).toContain("--tag");
    expect(calledArgs).toContain("my-session-tag");
  });

  it("should use default lines when lines parameter not specified", async () => {
    const params: TerminatorExecuteParams = {
      action: "read",
      project_path: "/Users/steipete/Projects/Terminator",
      tag: "test-session",
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: "Output with default lines",
      stderr: "",
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    await terminatorTool.handler(params, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain("--lines");
    expect(calledArgs).toContain(String(DEFAULT_LINES));
  });

  it("should call Swift CLI without tag when tag is missing (potential error case)", async () => {
    const params: TerminatorExecuteParams = {
      action: "read",
      project_path: "/Users/steipete/Projects/Terminator",
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: "",
      stderr: "No tag specified for read action",
      exitCode: 11, // SESSION_NOT_FOUND
      cancelled: false,
      internalTimeoutHit: false,
    });

    const result = await terminatorTool.handler(params, mockContext);

    expect(result.success).toBe(false);
    expect(result.message).toContain("Session not found");

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs[0]).toBe("read");
    expect(calledArgs).not.toContain("--tag");
  });

  it("should pass custom lines parameter when provided", async () => {
    const params: TerminatorExecuteParams = {
      action: "read",
      project_path: "/Users/steipete/Projects/Terminator",
      tag: "my-session",
      lines: 200,
    };

    mockedInvokeSwiftCLI.mockResolvedValue({
      stdout: "Output with custom lines",
      stderr: "",
      exitCode: 0,
      cancelled: false,
      internalTimeoutHit: false,
    });

    await terminatorTool.handler(params, mockContext);

    expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
    const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
    expect(calledArgs).toContain("--lines");
    expect(calledArgs).toContain("200");
  });
});
