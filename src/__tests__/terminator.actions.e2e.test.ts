/// <reference types="vitest/globals" />
import { describe, it, expect, beforeEach } from "vitest";
import { terminatorTool } from "../tool.js";
import type { TerminatorExecuteParams } from "../types.js";
import { mockedInvokeSwiftCLI, createMockContext } from "./e2e-test-setup.js";
import type { SdkCallContext } from "../types.js";

describe("Terminator MCP Tool - Kill, Focus, and Info Actions E2E Tests", () => {
  let mockContext: SdkCallContext;

  beforeEach(() => {
    mockedInvokeSwiftCLI.mockReset();
    mockContext = createMockContext();
  });

  describe("Kill Action", () => {
    it("should call Swift CLI with kill action and tag", async () => {
      const params: TerminatorExecuteParams = {
        action: "kill",
        project_path: "/Users/steipete/Projects/Terminator",
        tag: "session-to-kill",
      };

      mockedInvokeSwiftCLI.mockResolvedValue({
        stdout: "Process killed successfully",
        stderr: "",
        exitCode: 0,
        cancelled: false,
        internalTimeoutHit: false,
      });

      const result = await terminatorTool.handler(params, mockContext);

      expect(result.success).toBe(true);
      expect(result.message).toContain("Process killed successfully");

      expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
      const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
      expect(calledArgs[0]).toBe("kill");
      expect(calledArgs).toContain("--tag");
      expect(calledArgs).toContain("session-to-kill");
      expect(calledArgs).toContain("--json");
    });
  });

  describe("Focus Action", () => {
    it("should call Swift CLI with focus action and tag", async () => {
      const params: TerminatorExecuteParams = {
        action: "focus",
        project_path: "/Users/steipete/Projects/Terminator",
        tag: "session-to-focus",
      };

      mockedInvokeSwiftCLI.mockResolvedValue({
        stdout: "Session focused successfully",
        stderr: "",
        exitCode: 0,
        cancelled: false,
        internalTimeoutHit: false,
      });

      const result = await terminatorTool.handler(params, mockContext);

      expect(result.success).toBe(true);
      expect(result.message).toContain("Session focused successfully");

      expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
      const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
      expect(calledArgs[0]).toBe("focus");
      expect(calledArgs).toContain("--tag");
      expect(calledArgs).toContain("session-to-focus");
      expect(calledArgs).toContain("--json");
    });
  });

  describe("Info Action", () => {
    it("should return formatted info output", async () => {
      const params: TerminatorExecuteParams = {
        action: "info",
        project_path: "/Users/steipete/Projects/Terminator",
      };

      const mockInfo = {
        version: "1.0.0",
        configuration: {
          terminalApp: "iTerm",
          logLevel: "info",
          grouping: "smart",
        },
        dependencies: {
          iTerm: { installed: true, version: "3.4.0" },
        },
      };

      mockedInvokeSwiftCLI.mockResolvedValue({
        stdout: JSON.stringify(mockInfo),
        stderr: "",
        exitCode: 0,
        cancelled: false,
        internalTimeoutHit: false,
      });

      const result = await terminatorTool.handler(params, mockContext);

      expect(result.success).toBe(true);
      expect(result.message).toContain("Terminator Info");
      expect(result.message).toContain("Version: 1.0.0");
      expect(result.message).toContain("Terminal App: iTerm");

      expect(mockedInvokeSwiftCLI).toHaveBeenCalled();
      const calledArgs = mockedInvokeSwiftCLI.mock.calls[0][0];
      expect(calledArgs[0]).toBe("info");
      expect(calledArgs).toContain("--json");
    });

    it("should handle info command with missing dependencies", async () => {
      const params: TerminatorExecuteParams = {
        action: "info",
        project_path: "/Users/steipete/Projects/Terminator",
      };

      const mockInfo = {
        version: "1.0.0",
        configuration: {
          terminalApp: "Ghosty",
          logLevel: "warn",
        },
        dependencies: {
          Ghosty: { installed: false, error: "Not found" },
        },
      };

      mockedInvokeSwiftCLI.mockResolvedValue({
        stdout: JSON.stringify(mockInfo),
        stderr: "",
        exitCode: 0,
        cancelled: false,
        internalTimeoutHit: false,
      });

      const result = await terminatorTool.handler(params, mockContext);

      expect(result.success).toBe(true);
      expect(result.message).toContain("Not found");
    });
  });

  describe("Invalid Action", () => {
    it("should return error for invalid action", async () => {
      const params = {
        action: "nonExistentAction",
        project_path: "/Users/steipete/Projects/Terminator",
      } as unknown as TerminatorExecuteParams;

      const result = await terminatorTool.handler(params, mockContext);

      expect(result.success).toBe(false);
      expect(result.message).toContain("Invalid action 'nonExistentAction'");
      expect(mockedInvokeSwiftCLI).not.toHaveBeenCalled();
    });
  });
});
