import { pino } from "pino";
import type { Logger } from "pino";
import path from "path";
import fs from "fs";
import os from "os";

const PROJECT_NAME = "TERMINATOR";
const DEFAULT_LOG_DIR = path.join(
  os.homedir(),
  "Library",
  "Logs",
  "terminator-mcp",
);
const DEFAULT_LOG_FILE = "terminator.log";
const DEFAULT_LOG_LEVEL = "info";

function ensureDirectoryExists(dirPath: string): boolean {
  try {
    fs.mkdirSync(dirPath, { recursive: true });
    return true;
  } catch (error) {
    return false;
  }
}

function canWriteToPath(filePath: string): boolean {
  try {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      return ensureDirectoryExists(dir);
    }
    fs.accessSync(dir, fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

function getLogFilePath(): string {
  const envLogFile = process.env[`${PROJECT_NAME}_LOG_FILE`];

  if (envLogFile) {
    const absolutePath = path.isAbsolute(envLogFile)
      ? envLogFile
      : path.join(process.cwd(), envLogFile);

    if (canWriteToPath(absolutePath)) {
      return absolutePath;
    }

    // Silently fall back to default path - no console output per MCP best practices
  }

  const defaultPath = path.join(DEFAULT_LOG_DIR, DEFAULT_LOG_FILE);
  if (canWriteToPath(defaultPath)) {
    ensureDirectoryExists(DEFAULT_LOG_DIR);
    return defaultPath;
  }

  // Fall back to temp directory as last resort
  const tempPath = path.join(os.tmpdir(), "terminator-mcp", DEFAULT_LOG_FILE);
  ensureDirectoryExists(path.dirname(tempPath));
  return tempPath;
}

function getLogLevel(): string {
  const envLogLevel = process.env[`${PROJECT_NAME}_LOG_LEVEL`];
  if (envLogLevel) {
    const normalized = envLogLevel.toLowerCase();
    const validLevels = ["fatal", "error", "warn", "info", "debug", "trace"];
    if (validLevels.includes(normalized)) {
      return normalized;
    }
    // Silently use default log level - no console output per MCP best practices
  }
  return DEFAULT_LOG_LEVEL;
}

function shouldLogToConsole(): boolean {
  const consoleLogging = process.env[`${PROJECT_NAME}_CONSOLE_LOGGING`];
  return consoleLogging === "true" || consoleLogging === "1";
}

function createLogger(): Logger {
  const logFilePath = getLogFilePath();
  const logLevel = getLogLevel();
  const logToConsole = shouldLogToConsole();

  const streams: any[] = [
    {
      level: logLevel,
      stream: pino.destination({
        dest: logFilePath,
        sync: false,
        mkdir: true,
      }),
    },
  ];

  if (logToConsole) {
    streams.push({
      level: logLevel,
      stream: pino.transport({
        target: "pino-pretty",
        options: {
          colorize: true,
          ignore: "pid,hostname",
          translateTime: "HH:MM:ss.l",
        },
      }),
    });
  }

  return pino(
    {
      level: logLevel,
      formatters: {
        level: (label: string) => {
          return { level: label.toUpperCase() };
        },
      },
    },
    pino.multistream(streams),
  );
}

export const logger = createLogger();

export function flushLogger(): Promise<void> {
  return new Promise((resolve) => {
    logger.flush(() => {
      resolve();
    });
  });
}

export function getLoggerConfig() {
  const issues: string[] = [];
  const envLogFile = process.env[`${PROJECT_NAME}_LOG_FILE`];
  const envLogLevel = process.env[`${PROJECT_NAME}_LOG_LEVEL`];
  const actualLogFile = getLogFilePath();

  // Check log file path
  if (envLogFile) {
    const absolutePath = path.isAbsolute(envLogFile)
      ? envLogFile
      : path.join(process.cwd(), envLogFile);

    if (!canWriteToPath(absolutePath)) {
      issues.push(
        `Cannot write to log file path: ${absolutePath}. Using: ${actualLogFile}`,
      );
    }
  }

  // Check if using temp directory fallback
  const defaultPath = path.join(DEFAULT_LOG_DIR, DEFAULT_LOG_FILE);
  if (actualLogFile.includes(os.tmpdir()) && !canWriteToPath(defaultPath)) {
    issues.push(
      `Cannot write to default log directory. Using temp directory: ${actualLogFile}`,
    );
  }

  // Check log level
  if (envLogLevel) {
    const normalized = envLogLevel.toLowerCase();
    const validLevels = ["fatal", "error", "warn", "info", "debug", "trace"];
    if (!validLevels.includes(normalized)) {
      issues.push(
        `Invalid log level "${envLogLevel}". Using default: ${DEFAULT_LOG_LEVEL}`,
      );
    }
  }

  return {
    logFile: actualLogFile,
    logLevel: getLogLevel(),
    consoleLogging: shouldLogToConsole(),
    configurationIssues: issues,
  };
}
