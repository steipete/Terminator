import { describe, it, expect, beforeEach, vi } from "vitest";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

describe("logger", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();

    // Clear environment variables
    delete process.env.TERMINATOR_LOG_FILE;
    delete process.env.TERMINATOR_LOG_LEVEL;
    delete process.env.TERMINATOR_CONSOLE_LOGGING;

    // Mock fs and os modules
    vi.mock("fs");
    vi.mock("os");
    vi.mock("path");

    vi.mocked(os.homedir).mockReturnValue("/home/user");
    vi.mocked(fs.existsSync).mockReturnValue(true);
    vi.mocked(fs.mkdirSync).mockReturnValue(undefined);
    vi.mocked(fs.accessSync).mockReturnValue(undefined);
  });

  describe("getLogFilePath", () => {
    it("should use default log file path when no env var is set", async () => {
      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.logFile).toContain("terminator.log");
    });

    it("should use custom log file path from env var", async () => {
      process.env.TERMINATOR_LOG_FILE = "/custom/path/log.txt";
      vi.mocked(path.isAbsolute).mockReturnValue(true);

      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.logFile).toBe("/custom/path/log.txt");
    });

    it("should fall back to default when custom path is not writable", async () => {
      process.env.TERMINATOR_LOG_FILE = "/invalid/path/log.txt";
      vi.mocked(path.isAbsolute).mockReturnValue(true);
      vi.mocked(fs.existsSync).mockReturnValue(false);
      vi.mocked(fs.mkdirSync).mockImplementation(() => {
        throw new Error("Permission denied");
      });

      // Mock console.error to suppress warning
      const consoleError = vi
        .spyOn(console, "error")
        .mockImplementation(() => {});

      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.logFile).toContain("terminator.log");
      expect(consoleError).toHaveBeenCalledWith(
        expect.stringContaining("Cannot write to log file path"),
      );

      consoleError.mockRestore();
    });

    it("should resolve relative paths to absolute", async () => {
      process.env.TERMINATOR_LOG_FILE = "./logs/app.log";
      vi.mocked(path.isAbsolute).mockReturnValue(false);
      vi.mocked(path.join).mockReturnValue("/current/dir/logs/app.log");

      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.logFile).toBe("/current/dir/logs/app.log");
    });
  });

  describe("getLogLevel", () => {
    it("should use default log level when no env var is set", async () => {
      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.logLevel).toBe("info");
    });

    it.each(["debug", "info", "warn", "error", "fatal", "trace"])(
      'should accept valid log level "%s"',
      async (level) => {
        process.env.TERMINATOR_LOG_LEVEL = level;
        const { getLoggerConfig } = await import("../logger.js");
        const config = getLoggerConfig();
        expect(config.logLevel).toBe(level);
      },
    );

    it.each(["DEBUG", "INFO", "WARN"])(
      'should handle uppercase log level "%s"',
      async (level) => {
        process.env.TERMINATOR_LOG_LEVEL = level;
        const { getLoggerConfig } = await import("../logger.js");
        const config = getLoggerConfig();
        expect(config.logLevel).toBe(level.toLowerCase());
      },
    );

    it("should fall back to default for invalid log level", async () => {
      process.env.TERMINATOR_LOG_LEVEL = "invalid";

      // Mock console.error to suppress warning
      const consoleError = vi
        .spyOn(console, "error")
        .mockImplementation(() => {});

      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.logLevel).toBe("info");
      expect(consoleError).toHaveBeenCalledWith(
        expect.stringContaining("Invalid log level"),
      );

      consoleError.mockRestore();
    });
  });

  describe("shouldLogToConsole", () => {
    it("should return false by default", async () => {
      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.consoleLogging).toBe(false);
    });

    it.each(["true", "1"])('should return true for "%s"', async (value) => {
      process.env.TERMINATOR_CONSOLE_LOGGING = value;
      const { getLoggerConfig } = await import("../logger.js");
      const config = getLoggerConfig();
      expect(config.consoleLogging).toBe(true);
    });

    it.each(["false", "0", "yes", "on"])(
      'should return false for "%s"',
      async (value) => {
        process.env.TERMINATOR_CONSOLE_LOGGING = value;
        const { getLoggerConfig } = await import("../logger.js");
        const config = getLoggerConfig();
        expect(config.consoleLogging).toBe(false);
      },
    );
  });

  describe("logger instance", () => {
    it("should create a logger instance", async () => {
      const { logger } = await import("../logger.js");
      expect(logger).toBeDefined();
      expect(logger.info).toBeDefined();
      expect(logger.error).toBeDefined();
      expect(logger.debug).toBeDefined();
      expect(logger.warn).toBeDefined();
      expect(logger.fatal).toBeDefined();
    });
  });

  describe("flushLogger", () => {
    it("should flush the logger", async () => {
      const { logger, flushLogger } = await import("../logger.js");
      const flushSpy = vi
        .spyOn(logger, "flush")
        .mockImplementation((cb: any) => cb());

      await flushLogger();
      expect(flushSpy).toHaveBeenCalled();
    });
  });

  describe("ensureDirectoryExists", () => {
    it("should create directory recursively", async () => {
      vi.mocked(fs.mkdirSync).mockReturnValue(undefined);

      // Import and trigger logger creation
      await import("../logger.js");

      expect(fs.mkdirSync).toHaveBeenCalledWith(expect.any(String), {
        recursive: true,
      });
    });

    it("should handle directory creation failure gracefully", async () => {
      vi.mocked(fs.mkdirSync).mockImplementation(() => {
        throw new Error("Permission denied");
      });

      // Should not throw
      await expect(import("../logger.js")).resolves.toBeDefined();
    });
  });
});
