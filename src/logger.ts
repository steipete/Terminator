import { pino } from 'pino';
import type { Logger } from 'pino';
import path from 'path';
import fs from 'fs';
import os from 'os';

const PROJECT_NAME = 'TERMINATOR';
const DEFAULT_LOG_DIR = path.join(os.homedir(), 'Library', 'Logs', 'terminator-mcp');
const DEFAULT_LOG_FILE = 'terminator.log';
const DEFAULT_LOG_LEVEL = 'info';

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
    
    console.error(`Warning: Cannot write to log file path: ${absolutePath}. Falling back to default.`);
  }
  
  const defaultPath = path.join(DEFAULT_LOG_DIR, DEFAULT_LOG_FILE);
  ensureDirectoryExists(DEFAULT_LOG_DIR);
  return defaultPath;
}

function getLogLevel(): string {
  const envLogLevel = process.env[`${PROJECT_NAME}_LOG_LEVEL`];
  if (envLogLevel) {
    const normalized = envLogLevel.toLowerCase();
    const validLevels = ['fatal', 'error', 'warn', 'info', 'debug', 'trace'];
    if (validLevels.includes(normalized)) {
      return normalized;
    }
    console.error(`Warning: Invalid log level "${envLogLevel}". Using default: ${DEFAULT_LOG_LEVEL}`);
  }
  return DEFAULT_LOG_LEVEL;
}

function shouldLogToConsole(): boolean {
  const consoleLogging = process.env[`${PROJECT_NAME}_CONSOLE_LOGGING`];
  return consoleLogging === 'true' || consoleLogging === '1';
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
        target: 'pino-pretty',
        options: {
          colorize: true,
          ignore: 'pid,hostname',
          translateTime: 'HH:MM:ss.l',
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
  return {
    logFile: getLogFilePath(),
    logLevel: getLogLevel(),
    consoleLogging: shouldLogToConsole(),
    configurationIssues: [],
  };
}