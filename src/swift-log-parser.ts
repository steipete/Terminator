import { logger } from "./logger.js";

/**
 * Parse Swift CLI log lines and forward them to the pino logger
 * Swift log format: [2025-06-10T12:53:20.123Z INFO FileName.swift:42 functionName()] Log message
 */
export function parseAndLogSwiftOutput(stderr: string): void {
  if (!stderr) return;

  const lines = stderr.split("\n").filter((line) => line.trim());
  const logPattern =
    /^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\s+(\w+)\s+([^:]+):(\d+)\s+([^\]]+)\]\s+(.*)$/;

  for (const line of lines) {
    const match = line.match(logPattern);
    if (match) {
      const [_, timestamp, level, file, lineNum, func, message] = match;

      // Map Swift log levels to pino levels
      const pinoLevel = mapSwiftLevelToPino(level);

      // Log with context from Swift
      const logContext = {
        source: "swift-cli",
        swiftFile: file,
        swiftLine: lineNum,
        swiftFunction: func,
        timestamp: timestamp,
      };

      // Use specific logger methods based on level
      switch (pinoLevel) {
        case "fatal":
          logger.fatal(logContext, `[Swift] ${message}`);
          break;
        case "error":
          logger.error(logContext, `[Swift] ${message}`);
          break;
        case "warn":
          logger.warn(logContext, `[Swift] ${message}`);
          break;
        case "info":
          logger.info(logContext, `[Swift] ${message}`);
          break;
        case "debug":
          logger.debug(logContext, `[Swift] ${message}`);
          break;
        case "trace":
          logger.trace(logContext, `[Swift] ${message}`);
          break;
        default:
          logger.info(logContext, `[Swift] ${message}`);
      }
    } else {
      // Non-log format lines (like raw output)
      if (line.trim()) {
        logger.debug({ source: "swift-cli" }, `[Swift] ${line}`);
      }
    }
  }
}

function mapSwiftLevelToPino(swiftLevel: string): string {
  const levelMap: Record<string, string> = {
    FATAL: "fatal",
    ERROR: "error",
    WARN: "warn",
    INFO: "info",
    DEBUG: "debug",
    TRACE: "trace",
  };

  return levelMap[swiftLevel.toUpperCase()] || "info";
}

/**
 * Create a line-by-line processor for streaming Swift logs
 */
export function createSwiftLogProcessor() {
  let buffer = "";

  return {
    process(chunk: string): void {
      buffer += chunk;
      const lines = buffer.split("\n");

      // Keep the last incomplete line in the buffer
      buffer = lines.pop() || "";

      // Process complete lines
      for (const line of lines) {
        if (line.trim()) {
          parseAndLogSwiftOutput(line);
        }
      }
    },

    flush(): void {
      if (buffer.trim()) {
        parseAndLogSwiftOutput(buffer);
        buffer = "";
      }
    },
  };
}
