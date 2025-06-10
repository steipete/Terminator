import { TerminatorExecuteParams } from "./types.js";
import { logger } from "./logger.js";
import * as fs from "node:fs";
import * as path from "node:path";

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

export function validateExecuteParams(params: any): ValidationResult {
  const errors: string[] = [];

  // Validate action
  if (params.action !== undefined) {
    const validActions = [
      "execute",
      "read",
      "sessions",
      "info",
      "focus",
      "kill",
    ];
    if (typeof params.action !== "string") {
      errors.push(`Action must be a string, got ${typeof params.action}`);
    } else if (!validActions.includes(params.action)) {
      errors.push(
        `Invalid action '${params.action}'. Must be one of: ${validActions.join(", ")}`,
      );
    }
  }

  // Validate project_path (required)
  if (!params.project_path) {
    errors.push("project_path is required");
  } else if (typeof params.project_path !== "string") {
    errors.push(
      `project_path must be a string, got ${typeof params.project_path}`,
    );
  } else if (params.project_path.trim() === "") {
    errors.push("project_path cannot be empty");
  }

  // Validate tag
  if (params.tag !== undefined) {
    if (typeof params.tag !== "string" && typeof params.tag !== "number") {
      errors.push(`tag must be a string or number, got ${typeof params.tag}`);
    }
  }

  // Validate command
  if (params.command !== undefined) {
    if (typeof params.command !== "string") {
      errors.push(`command must be a string, got ${typeof params.command}`);
    }
  }

  // Validate background
  if (params.background !== undefined) {
    if (
      typeof params.background !== "boolean" &&
      typeof params.background !== "string"
    ) {
      errors.push(
        `background must be a boolean or string, got ${typeof params.background}`,
      );
    }
  }

  // Validate lines
  if (params.lines !== undefined) {
    if (typeof params.lines === "number") {
      if (params.lines < 1 || params.lines > 10000) {
        errors.push("lines must be between 1 and 10000");
      }
    } else if (typeof params.lines === "string") {
      const parsed = parseInt(params.lines, 10);
      if (isNaN(parsed) || parsed < 1 || parsed > 10000) {
        errors.push("lines must be a valid number between 1 and 10000");
      }
    } else {
      errors.push(
        `lines must be a number or string, got ${typeof params.lines}`,
      );
    }
  }

  // Validate timeout
  if (params.timeout !== undefined) {
    if (typeof params.timeout === "number") {
      if (params.timeout < 0 || params.timeout > 3600) {
        errors.push("timeout must be between 0 and 3600 seconds");
      }
    } else if (typeof params.timeout === "string") {
      const parsed = parseInt(params.timeout, 10);
      if (isNaN(parsed) || parsed < 0 || parsed > 3600) {
        errors.push(
          "timeout must be a valid number between 0 and 3600 seconds",
        );
      }
    } else {
      errors.push(
        `timeout must be a number or string, got ${typeof params.timeout}`,
      );
    }
  }

  // Validate focus
  if (params.focus !== undefined) {
    if (typeof params.focus !== "boolean" && typeof params.focus !== "string") {
      errors.push(
        `focus must be a boolean or string, got ${typeof params.focus}`,
      );
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

export function sanitizePath(inputPath: string): string | null {
  try {
    // Remove any null bytes
    const cleanPath = inputPath.replace(/\0/g, "");

    // Normalize the path
    const normalized = path.normalize(cleanPath);

    // Check for path traversal attempts
    if (normalized.includes("..")) {
      logger.warn({ path: inputPath }, "Path traversal attempt detected");
      return null;
    }

    return normalized;
  } catch (error) {
    logger.error({ error, path: inputPath }, "Error sanitizing path");
    return null;
  }
}

export function validateFileAccess(
  filePath: string,
  mode: number = fs.constants.R_OK,
): boolean {
  try {
    fs.accessSync(filePath, mode);
    return true;
  } catch (error) {
    return false;
  }
}

export function validateEnvironmentVariables(): string[] {
  const issues: string[] = [];

  // Check log file writability
  const logFile = process.env.TERMINATOR_LOG_FILE;
  if (logFile) {
    const sanitized = sanitizePath(logFile);
    if (!sanitized) {
      issues.push(`Invalid TERMINATOR_LOG_FILE path: ${logFile}`);
    } else {
      const dir = path.dirname(sanitized);
      if (!validateFileAccess(dir, fs.constants.W_OK)) {
        issues.push(`Cannot write to log directory: ${dir}`);
      }
    }
  }

  // Check log level validity
  const logLevel = process.env.TERMINATOR_LOG_LEVEL;
  if (logLevel) {
    const validLevels = ["fatal", "error", "warn", "info", "debug", "trace"];
    if (!validLevels.includes(logLevel.toLowerCase())) {
      issues.push(
        `Invalid TERMINATOR_LOG_LEVEL: ${logLevel}. Valid levels: ${validLevels.join(", ")}`,
      );
    }
  }

  // Check terminal app validity
  const terminalApp = process.env.TERMINATOR_APP;
  if (terminalApp) {
    const validApps = ["iTerm", "Terminal", "Ghostty"];
    if (!validApps.includes(terminalApp)) {
      issues.push(
        `Invalid TERMINATOR_APP: ${terminalApp}. Valid apps: ${validApps.join(", ")}`,
      );
    }
  }

  return issues;
}
