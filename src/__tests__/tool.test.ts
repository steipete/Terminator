import { describe, it, expect, beforeEach, vi } from "vitest";
import { terminatorTool } from "../tool.js";
import * as swiftCli from "../swift-cli.js";
import * as utils from "../utils.js";
import * as fs from "node:fs";

vi.mock("../swift-cli.js");
vi.mock("../utils.js");
vi.mock("../logger.js");
vi.mock("node:fs");

describe("terminatorTool", () => {
  let mockContext: any;

  beforeEach(() => {
    vi.clearAllMocks();

    mockContext = {
      abortSignal: {
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        aborted: false,
      },
    };

    vi.mocked(utils.resolveEffectiveProjectPath).mockReturnValue(
      "/path/to/project",
    );
    vi.mocked(utils.resolveDefaultTag).mockReturnValue("test-tag");
    vi.mocked(utils.formatCliOutputForAI).mockReturnValue("Formatted output");
    vi.mocked(fs.existsSync).mockReturnValue(true);
    vi.mocked(fs.accessSync).mockReturnValue(undefined);
  });

  describe("tool definition", () => {
    it("should have correct name and description", () => {
      expect(terminatorTool.name).toBe("execute");
      expect(terminatorTool.description).toContain(
        "Manages macOS terminal sessions",
      );
    });

    it("should have correct input schema", () => {
      const schema = terminatorTool.inputSchema;
      expect(schema.type).toBe("object");
      expect(schema.required).toEqual(["project_path"]);
      expect(schema.properties.action.enum).toEqual([
        "execute",
        "read",
        "sessions",
        "info",
        "focus",
        "kill",
      ]);
    });

    it("should have correct output schema", () => {
      const schema = terminatorTool.outputSchema;
      expect(schema.type).toBe("object");
      expect(schema.required).toEqual(["success", "message"]);
    });
  });

  describe("handler", () => {
    it("should handle execute action with default parameters", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "echo hello",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"execResult": {"output": "hello"}}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining([
          "execute",
          "test-tag",
          "--project-path",
          "/path/to/project",
          "--command",
          "echo hello",
        ]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should default action to execute when not provided", async () => {
      const params = {
        project_path: "/path/to/project",
        command: "ls",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"execResult": {"output": "file1\\nfile2"}}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["execute"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle read action", async () => {
      const params = {
        action: "read",
        project_path: "/path/to/project",
        tag: "my-session",
        lines: 50,
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"readOutput": "Session output"}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["read", "my-session", "--lines", "50"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle sessions action", async () => {
      const params = {
        action: "sessions",
        project_path: "/path/to/project",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '[{"tag": "session1"}, {"tag": "session2"}]',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["sessions", "--json"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle info action with logger configuration", async () => {
      const params = {
        action: "info",
        project_path: "/path/to/project",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"version": "1.0.0", "app": "iTerm"}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      const message = JSON.parse(result.message);
      expect(message).toHaveProperty("version");
      expect(message).toHaveProperty("logger");
      expect(message).toHaveProperty("swiftCLI");
      expect(message.logger).toHaveProperty("logFile");
      expect(message.logger).toHaveProperty("logLevel");
    });

    it("should handle focus action", async () => {
      const params = {
        action: "focus",
        project_path: "/path/to/project",
        tag: "my-session",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: "Window focused",
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining([
          "focus",
          "my-session",
          "--focus-mode",
          "force-focus",
        ]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle kill action", async () => {
      const params = {
        action: "kill",
        project_path: "/path/to/project",
        tag: "my-session",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: "Process killed",
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["kill", "my-session"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should reject invalid action", async () => {
      const params = {
        action: "invalid",
        project_path: "/path/to/project",
      };

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(false);
      expect(result.message).toContain("Invalid action");
    });

    it("should handle missing project path", async () => {
      const params = {
        action: "execute",
        project_path: "/non/existent/path",
      };

      vi.mocked(utils.resolveEffectiveProjectPath).mockReturnValue(null);

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(false);
      expect(result.message).toContain("could not be resolved");
    });

    it("should handle background execution", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "npm start",
        background: true,
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"execResult": {"output": "Started"}}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["--background"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle custom timeout", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "sleep 5",
        timeout: 10,
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"execResult": {"output": "Done"}}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["--timeout", "10"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle focus mode option", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "echo test",
        focus: false,
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"execResult": {"output": "test"}}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining(["--focus-mode", "no-focus"]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });

    it("should handle process cancellation", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "long-running",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: "",
        stderr: "",
        exitCode: null,
        internalTimeoutHit: false,
        cancelled: true,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(false);
      expect(result.message).toContain("cancelled");
    });

    it("should handle internal timeout", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "hanging-command",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: "",
        stderr: "",
        exitCode: null,
        internalTimeoutHit: true,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(false);
      expect(result.message).toContain("unresponsive");
    });

    it("should handle Swift CLI errors with exit codes", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        command: "test",
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: "",
        stderr: "Configuration error occurred",
        exitCode: 2,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(false);
      expect(result.message).toContain("Configuration Error");
      expect(result.message).toContain("Swift CLI Code 2");
    });

    it("should handle parameter aliases", async () => {
      const params = {
        action: "execute",
        project_path: "/path/to/project",
        cmd: "echo test", // alias for command
        bg: true, // alias for background
        timeoutseconds: 30, // alias for timeout
      };

      vi.mocked(swiftCli.invokeSwiftCLI).mockResolvedValue({
        stdout: '{"execResult": {"output": "test"}}',
        stderr: "",
        exitCode: 0,
        internalTimeoutHit: false,
        cancelled: false,
      });

      const result = await terminatorTool.handler(params as any, mockContext);

      expect(result.success).toBe(true);
      expect(swiftCli.invokeSwiftCLI).toHaveBeenCalledWith(
        expect.arrayContaining([
          "--command",
          "echo test",
          "--background",
          "--timeout",
          "30",
        ]),
        expect.any(Object),
        mockContext,
        expect.any(Number),
      );
    });
  });
});
