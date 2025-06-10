import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  parseAndLogSwiftOutput,
  createSwiftLogProcessor,
} from "../swift-log-parser.js";
import { logger } from "../logger.js";

// Mock the logger
vi.mock("../logger.js", () => ({
  logger: {
    fatal: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
    trace: vi.fn(),
  },
}));

describe("Swift Log Parser", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("parseAndLogSwiftOutput", () => {
    it("should parse and forward Swift log lines to pino", () => {
      const swiftLog =
        "[2025-06-10T12:53:20.123Z INFO ProcessResponsibility.swift:33 disclaimParentResponsibility()] Attempting to re-spawn as self-responsible process";

      parseAndLogSwiftOutput(swiftLog);

      expect(logger.info).toHaveBeenCalledWith(
        {
          source: "swift-cli",
          swiftFile: "ProcessResponsibility.swift",
          swiftLine: "33",
          swiftFunction: "disclaimParentResponsibility()",
          timestamp: "2025-06-10T12:53:20.123Z",
        },
        "[Swift] Attempting to re-spawn as self-responsible process",
      );
    });

    it("should handle multiple log lines", () => {
      const swiftLogs = `[2025-06-10T12:53:20.123Z INFO File1.swift:10 func1()] First message
[2025-06-10T12:53:20.124Z DEBUG File2.swift:20 func2()] Second message
[2025-06-10T12:53:20.125Z ERROR File3.swift:30 func3()] Third message`;

      parseAndLogSwiftOutput(swiftLogs);

      expect(logger.info).toHaveBeenCalledTimes(1);
      expect(logger.debug).toHaveBeenCalledTimes(1);
      expect(logger.error).toHaveBeenCalledTimes(1);
    });

    it("should map Swift log levels to pino levels correctly", () => {
      const testCases = [
        { level: "FATAL", expected: "fatal" },
        { level: "ERROR", expected: "error" },
        { level: "WARN", expected: "warn" },
        { level: "INFO", expected: "info" },
        { level: "DEBUG", expected: "debug" },
        { level: "TRACE", expected: "trace" },
      ];

      for (const { level, expected } of testCases) {
        const log = `[2025-06-10T12:53:20.123Z ${level} Test.swift:1 test()] Test message`;
        parseAndLogSwiftOutput(log);

        const loggerMethod = logger[expected as keyof typeof logger];
        expect(loggerMethod).toHaveBeenCalled();
      }
    });

    it("should handle non-log format lines", () => {
      const mixedOutput = `Regular output line
[2025-06-10T12:53:20.123Z INFO Test.swift:1 test()] Log message
Another regular line`;

      parseAndLogSwiftOutput(mixedOutput);

      expect(logger.info).toHaveBeenCalledTimes(1);
      expect(logger.debug).toHaveBeenCalledTimes(2); // Two non-log lines
    });

    it("should ignore empty lines", () => {
      const outputWithEmptyLines = `
[2025-06-10T12:53:20.123Z INFO Test.swift:1 test()] Message

`;

      parseAndLogSwiftOutput(outputWithEmptyLines);

      expect(logger.info).toHaveBeenCalledTimes(1);
      expect(logger.debug).not.toHaveBeenCalled();
    });
  });

  describe("createSwiftLogProcessor", () => {
    it("should process chunks and handle line buffering", () => {
      const processor = createSwiftLogProcessor();

      // Send incomplete line
      processor.process(
        "[2025-06-10T12:53:20.123Z INFO Test.swift:1 test()] Incom",
      );
      expect(logger.info).not.toHaveBeenCalled();

      // Complete the line
      processor.process("plete message\n");
      expect(logger.info).toHaveBeenCalledWith(
        {
          source: "swift-cli",
          swiftFile: "Test.swift",
          swiftLine: "1",
          swiftFunction: "test()",
          timestamp: "2025-06-10T12:53:20.123Z",
        },
        "[Swift] Incomplete message",
      );
    });

    it("should flush remaining buffer content", () => {
      const processor = createSwiftLogProcessor();

      // Send incomplete line
      processor.process(
        "[2025-06-10T12:53:20.123Z INFO Test.swift:1 test()] Buffered message",
      );
      expect(logger.info).not.toHaveBeenCalled();

      // Flush should process the buffered content
      processor.flush();
      expect(logger.info).toHaveBeenCalledWith(
        {
          source: "swift-cli",
          swiftFile: "Test.swift",
          swiftLine: "1",
          swiftFunction: "test()",
          timestamp: "2025-06-10T12:53:20.123Z",
        },
        "[Swift] Buffered message",
      );
    });

    it("should handle multiple lines in one chunk", () => {
      const processor = createSwiftLogProcessor();

      const chunk = `[2025-06-10T12:53:20.123Z INFO Test.swift:1 test()] Line 1\n[2025-06-10T12:53:20.124Z DEBUG Test.swift:2 test()] Line 2\n[2025-06-10T12:53:20.125Z ERROR Test.swift:3 test()] Line 3\n`;

      processor.process(chunk);

      expect(logger.info).toHaveBeenCalledTimes(1);
      expect(logger.debug).toHaveBeenCalledTimes(1);
      expect(logger.error).toHaveBeenCalledTimes(1);
    });
  });
});
