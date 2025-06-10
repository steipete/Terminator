import { describe, it, expect, vi, beforeEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import {
  expandTilde,
  resolveEffectiveProjectPath,
  resolveDefaultTag,
  formatCliOutputForAI,
  extractOutputForAction,
} from "../utils.js";

vi.mock("node:fs");
vi.mock("node:path");
vi.mock("node:os");

describe("utils", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("expandTilde", () => {
    it("should expand tilde to home directory", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");
      vi.mocked(path.join).mockImplementation((...args) => args.join("/"));

      expect(expandTilde("~/Desktop")).toBe("/Users/testuser/Desktop");
    });

    it("should not expand paths without tilde", () => {
      expect(expandTilde("/absolute/path")).toBe("/absolute/path");
      expect(expandTilde("./relative/path")).toBe("./relative/path");
    });

    it("should handle tilde at the beginning only", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");
      vi.mocked(path.join).mockImplementation((...args) => args.join("/"));

      expect(expandTilde("~/Documents/~notexpanded")).toBe(
        "/Users/testuser/Documents/~notexpanded",
      );
    });

    it("should handle just tilde with slash", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");

      expect(expandTilde("~/")).toBe("/Users/testuser");
    });

    it("should not expand tilde in the middle of path", () => {
      expect(expandTilde("/path/~/to/file")).toBe("/path/~/to/file");
    });

    it("should handle empty string", () => {
      expect(expandTilde("")).toBe("");
    });

    it("should handle paths with multiple slashes", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");
      vi.mocked(path.join).mockImplementation((...args) =>
        args.filter(Boolean).join("/"),
      );

      expect(expandTilde("~//Documents//Projects")).toBe(
        "/Users/testuser/Documents/Projects",
      );
    });

    it("should handle tilde with spaces", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/test user");
      vi.mocked(path.join).mockImplementation((...args) => args.join("/"));

      expect(expandTilde("~/My Documents")).toBe(
        "/Users/test user/My Documents",
      );
    });
  });

  describe("resolveEffectiveProjectPath", () => {
    it("should expand tilde paths", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");
      vi.mocked(path.join).mockImplementation((...args) => args.join("/"));
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      const result = resolveEffectiveProjectPath("~/Desktop", "/fallback");
      expect(result).toBe("/Users/testuser/Desktop");
    });

    it("should create non-existent directories", () => {
      const newPath = "/new/directory/path";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(false);
      vi.mocked(fs.mkdirSync).mockImplementation(() => undefined);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      const result = resolveEffectiveProjectPath(newPath, "/fallback");

      expect(vi.mocked(fs.mkdirSync)).toHaveBeenCalledWith(newPath, {
        recursive: true,
      });
      expect(result).toBe(newPath);
    });

    it("should return null if directory creation fails", () => {
      const newPath = "/new/directory/path";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(false);
      vi.mocked(fs.mkdirSync).mockImplementation(() => {
        throw new Error("Permission denied");
      });

      const result = resolveEffectiveProjectPath(newPath, "/fallback");
      expect(result).toBeNull();
    });

    it("should return absolute path as-is when it exists", () => {
      const absolutePath = "/absolute/path/to/project";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath(absolutePath, "/fallback")).toBe(
        absolutePath,
      );
    });

    it("should resolve relative path from current directory", () => {
      const relativePath = "./relative/path";
      const resolvedPath = "/resolved/absolute/path";
      vi.mocked(path.isAbsolute).mockReturnValue(false);
      vi.mocked(path.resolve).mockReturnValue(resolvedPath);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath(relativePath, "/fallback")).toBe(
        resolvedPath,
      );
    });

    it("should use fallback path when primary path is null", () => {
      const fallbackPath = "/fallback/path";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath(null as any, fallbackPath)).toBe(
        fallbackPath,
      );
    });

    it("should return null when path exists but is not a directory", () => {
      const filePath = "/path/to/file.txt";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => false,
      } as any);

      expect(resolveEffectiveProjectPath(filePath, "/fallback")).toBeNull();
    });

    it("should handle symlinked directories like /tmp", () => {
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath("/tmp", "/fallback")).toBe("/tmp");
    });

    it("should handle nested tilde paths", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");
      vi.mocked(path.join).mockImplementation((...args) => args.join("/"));
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      const result = resolveEffectiveProjectPath(
        "~/Documents/Projects/my-app",
        "/fallback",
      );
      expect(result).toBe("/Users/testuser/Documents/Projects/my-app");
    });

    it("should handle empty string path", () => {
      expect(resolveEffectiveProjectPath("", "/fallback")).toBe("/fallback");
    });

    it("should handle undefined path with undefined fallback", () => {
      expect(resolveEffectiveProjectPath(undefined, undefined)).toBeNull();
    });

    it("should handle whitespace-only paths", () => {
      expect(resolveEffectiveProjectPath("   ", "/fallback")).toBe("/fallback");
    });

    it("should create deeply nested directories", () => {
      const deepPath = "/very/deep/nested/directory/structure";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(false);
      vi.mocked(fs.mkdirSync).mockImplementation(() => undefined);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      const result = resolveEffectiveProjectPath(deepPath, "/fallback");

      expect(vi.mocked(fs.mkdirSync)).toHaveBeenCalledWith(deepPath, {
        recursive: true,
      });
      expect(result).toBe(deepPath);
    });

    it("should handle paths with special characters", () => {
      const specialPath = "/path/with spaces/and-special_chars!";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath(specialPath, "/fallback")).toBe(
        specialPath,
      );
    });

    it("should handle relative paths with tilde", () => {
      vi.mocked(os.homedir).mockReturnValue("/Users/testuser");
      vi.mocked(path.join).mockImplementation((...args) => args.join("/"));
      vi.mocked(path.isAbsolute).mockReturnValue(false);
      vi.mocked(path.resolve).mockReturnValue("/Users/testuser/relative/path");
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      const result = resolveEffectiveProjectPath(
        "~/relative/path",
        "/fallback",
      );
      expect(result).toBe("/Users/testuser/relative/path");
    });

    it("should handle stat errors gracefully", () => {
      const errorPath = "/error/path";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockImplementation(() => {
        throw new Error("EACCES: permission denied");
      });

      expect(resolveEffectiveProjectPath(errorPath, "/fallback")).toBeNull();
    });

    it("should handle concurrent directory creation attempts", () => {
      const concurrentPath = "/concurrent/path";
      vi.mocked(path.isAbsolute).mockReturnValue(true);

      // First check returns false, but mkdir fails because another process created it
      vi.mocked(fs.existsSync).mockReturnValueOnce(false).mockReturnValue(true);
      vi.mocked(fs.mkdirSync).mockImplementation(() => {
        throw new Error("EEXIST: file already exists");
      });
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      // Should still succeed because it exists after the failed mkdir
      const result = resolveEffectiveProjectPath(concurrentPath, "/fallback");
      expect(result).toBe(concurrentPath);
    });

    it("should properly handle root directory", () => {
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath("/", undefined)).toBe("/");
    });

    it("should handle network paths on macOS", () => {
      const networkPath = "/Volumes/NetworkDrive/project";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(true);
      vi.mocked(fs.statSync).mockReturnValue({
        isDirectory: () => true,
      } as any);

      expect(resolveEffectiveProjectPath(networkPath, "/fallback")).toBe(
        networkPath,
      );
    });
  });

  describe("resolveDefaultTag", () => {
    it("should return tag value if provided", () => {
      expect(resolveDefaultTag("custom-tag", "/any/path")).toBe("custom-tag");
    });

    it("should return null if tag is empty string", () => {
      expect(resolveDefaultTag("", "/any/path")).toBeNull();
    });

    it("should generate tag from project path when tag is not provided", () => {
      vi.mocked(path.basename).mockReturnValue("project-name");
      expect(resolveDefaultTag(undefined, "/path/to/project-name")).toBe(
        "project-name",
      );
    });

    it("should return null when neither tag nor project path is provided", () => {
      expect(resolveDefaultTag(undefined, undefined)).toBeNull();
    });

    it("should handle numeric tag values", () => {
      expect(resolveDefaultTag(123 as any, "/any/path")).toBe("123");
    });
  });

  describe("extractOutputForAction", () => {
    it('should extract read output for action "read"', () => {
      const jsonData = { readOutput: "test output" };
      expect(extractOutputForAction("read", jsonData)).toBe("test output");
    });

    it('should extract exec output for action "execute"', () => {
      const jsonData = { execResult: { output: "exec output" } };
      expect(extractOutputForAction("execute", jsonData)).toBe("exec output");
    });

    it('should return formatted JSON for action "sessions"', () => {
      const jsonData = { sessions: ["session1", "session2"] };
      expect(extractOutputForAction("sessions", jsonData)).toBe(
        JSON.stringify(jsonData, null, 2),
      );
    });

    it('should return formatted JSON for action "info"', () => {
      const jsonData = { version: "1.0.0", app: "iTerm" };
      expect(extractOutputForAction("info", jsonData)).toBe(
        JSON.stringify(jsonData, null, 2),
      );
    });

    it("should return null for unsupported actions", () => {
      expect(extractOutputForAction("unsupported", {})).toBeNull();
    });
  });

  describe("formatCliOutputForAI", () => {
    const mockResult = {
      stdout: "",
      stderr: "",
      exitCode: 0,
      internalTimeoutHit: false,
      cancelled: false,
    };

    it("should format exec output with command details", () => {
      const jsonOutput = JSON.stringify({
        execResult: { output: "Command output" },
      });
      const result = { ...mockResult, stdout: jsonOutput };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "npm test",
        "test-tag",
        false,
        30,
      );
      expect(formatted).toContain("Command output");
      expect(formatted).toContain("npm test");
      expect(formatted).toContain("test-tag");
    });

    it("should format read output", () => {
      const jsonOutput = JSON.stringify({ readOutput: "Session output" });
      const result = { ...mockResult, stdout: jsonOutput };

      const formatted = formatCliOutputForAI(
        "read",
        result,
        undefined,
        "test-tag",
        false,
      );
      expect(formatted).toContain("Session output");
    });

    it("should format list output as JSON", () => {
      const sessions = [{ tag: "session1" }, { tag: "session2" }];
      const jsonOutput = JSON.stringify(sessions);
      const result = { ...mockResult, stdout: jsonOutput };

      const formatted = formatCliOutputForAI(
        "sessions",
        result,
        undefined,
        undefined,
        false,
      );
      expect(formatted).toContain("session1");
      expect(formatted).toContain("session2");
    });

    it("should handle kill action output", () => {
      const result = { ...mockResult, stdout: "Process killed" };

      const formatted = formatCliOutputForAI(
        "kill",
        result,
        undefined,
        "test-tag",
        false,
      );
      expect(formatted).toContain("test-tag");
      expect(formatted).toContain("killed");
    });

    it("should handle focus action output", () => {
      const result = { ...mockResult, stdout: "Window focused" };

      const formatted = formatCliOutputForAI(
        "focus",
        result,
        undefined,
        "test-tag",
        false,
      );
      expect(formatted).toContain("test-tag");
      expect(formatted).toContain("focused");
    });

    it("should handle JSON parsing errors gracefully", () => {
      const result = { ...mockResult, stdout: "Invalid JSON" };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "echo test",
        "test-tag",
        false,
      );
      expect(formatted).toContain("Invalid JSON");
    });

    it("should include background execution details", () => {
      const jsonOutput = JSON.stringify({
        execResult: { output: "Background output" },
      });
      const result = { ...mockResult, stdout: jsonOutput };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "npm start",
        "test-tag",
        true,
      );
      expect(formatted).toContain("background");
    });

    it("should handle empty command execution", () => {
      const result = { ...mockResult, stdout: "" };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "",
        "test-tag",
        false,
      );
      expect(formatted).toBe("Terminator: Session 'test-tag' prepared.");
    });

    it("should handle timeout in output", () => {
      const result = {
        ...mockResult,
        stdout: "Execution timed out after 30 seconds",
      };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "sleep 100",
        "test-tag",
        false,
        30,
      );
      expect(formatted).toContain("timed out after 30s");
    });

    it("should handle stderr output for exec", () => {
      const result = { ...mockResult, stderr: "Error: Command failed" };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "invalid-cmd",
        "test-tag",
        false,
      );
      expect(formatted).toContain("Error Output: Error: Command failed");
    });

    it("should handle empty list result", () => {
      const result = { ...mockResult, stdout: "[]" };

      const formatted = formatCliOutputForAI(
        "sessions",
        result,
        undefined,
        undefined,
        false,
      );
      expect(formatted).toBe("Terminator: No active sessions found.");
    });

    it("should handle list with multiple sessions", () => {
      const sessions = [
        { project_name: "Project1", task_tag: "build", is_busy: true },
        {
          project_name: "Project2",
          session_identifier: "test",
          is_busy: false,
        },
      ];
      const result = { ...mockResult, stdout: JSON.stringify(sessions) };

      const formatted = formatCliOutputForAI(
        "sessions",
        result,
        undefined,
        undefined,
        false,
      );
      expect(formatted).toContain("Found 2 session(s)");
      expect(formatted).toContain("🤖💥 Project1 / build (Busy)");
      expect(formatted).toContain("🤖💥 Project2 / test (Idle)");
    });

    it("should handle info with no sessions", () => {
      const infoData = {
        version: "1.0.0",
        configuration: {
          TERMINATOR_APP: "iTerm",
          TERMINATOR_WINDOW_GROUPING: "smart",
        },
        sessions: [],
      };
      const result = { ...mockResult, stdout: JSON.stringify(infoData) };

      const formatted = formatCliOutputForAI(
        "info",
        result,
        undefined,
        undefined,
        false,
      );
      expect(formatted).toContain("Terminator v1.0.0");
      expect(formatted).toContain("App=iTerm");
      expect(formatted).toContain("Sessions: 0");
    });

    it("should handle malformed JSON gracefully", () => {
      const result = { ...mockResult, stdout: "{invalid json" };

      const formatted = formatCliOutputForAI(
        "sessions",
        result,
        undefined,
        undefined,
        false,
      );
      expect(formatted).toContain("output parsing failed");
      expect(formatted).toContain("{invalid json");
    });

    it("should handle successful kill action", () => {
      const result = {
        ...mockResult,
        exitCode: 0,
        stdout: "Process terminated",
      };

      const formatted = formatCliOutputForAI(
        "kill",
        result,
        undefined,
        "build-tag",
        false,
      );
      expect(formatted).toContain("successfully targeted for termination");
      expect(formatted).toContain("build-tag");
    });

    it("should handle failed kill action", () => {
      const result = { ...mockResult, exitCode: 1, stdout: "No such process" };

      const formatted = formatCliOutputForAI(
        "kill",
        result,
        undefined,
        "missing-tag",
        false,
      );
      expect(formatted).toContain("could not be killed");
      expect(formatted).toContain("missing-tag");
    });

    it("should handle focus action with output", () => {
      const result = { ...mockResult, stdout: "Window brought to front" };

      const formatted = formatCliOutputForAI(
        "focus",
        result,
        undefined,
        "ui-tag",
        false,
      );
      expect(formatted).toContain("focused");
      expect(formatted).toContain("ui-tag");
    });

    it("should handle unknown action", () => {
      const result = { ...mockResult, stdout: "Some output" };

      const formatted = formatCliOutputForAI(
        "unknown" as any,
        result,
        undefined,
        undefined,
        false,
      );
      expect(formatted).toBe("Some output");
    });

    it("should handle background timeout correctly", () => {
      const result = { ...mockResult, stdout: "Command execution timed out" };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "npm start",
        "server",
        true,
      );
      expect(formatted).toContain("timed out after 5s"); // DEFAULT_BACKGROUND_STARTUP_SECONDS
    });

    it("should handle foreground timeout with custom value", () => {
      const result = { ...mockResult, stderr: "Execution timed out" };

      const formatted = formatCliOutputForAI(
        "execute",
        result,
        "build.sh",
        "build",
        false,
        120,
      );
      expect(formatted).toContain("timed out after 120s");
    });
  });
});
