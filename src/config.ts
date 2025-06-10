// Manages configuration loading, environment variables, default values,
// and a.tsliOption parsing for the Terminator MCP tool.
import { TerminatorOptions } from "./types.js";
import * as fs from "node:fs"; // Import fs for file operations
import * as path from "node:path"; // Import path for joining
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { logger } from "./logger.js";

// Get version from package.json
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const packageJsonPath = path.resolve(__dirname, "..", "package.json");
const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"));
export const SERVER_VERSION = packageJson.version || "unknown";

// --- Utility Functions ---

// Logger is now handled by pino in logger.ts

export function debugLog(message: string, ...args: any[]) {
  logger.debug({ args }, message);
}

// --- Configuration Loading (as per SDD 3.1.2 for dynamic description) ---
export function getEnvVar(key: string, defaultValue: string): string {
  return process.env[key] || defaultValue;
}

export function getEnvVarInt(key: string, defaultValue: number): number {
  const valStr = process.env[key];
  if (valStr === undefined || valStr === null || valStr.trim() === "")
    return defaultValue;
  const parsed = parseInt(valStr, 10);
  return isNaN(parsed) ? defaultValue : parsed;
}

export function getEnvVarBool(key: string, defaultValue: boolean): boolean {
  const val = process.env[key]?.toLowerCase();
  if (val === undefined) return defaultValue;
  return ["true", "1", "t", "yes", "on"].includes(val);
}

export const CURRENT_TERMINAL_APP = getEnvVar("TERMINATOR_APP", "iTerm");
export const DEFAULT_BACKGROUND_STARTUP_SECONDS = getEnvVarInt(
  "TERMINATOR_BACKGROUND_STARTUP_SECONDS",
  5,
);
export const DEFAULT_FOREGROUND_COMPLETION_SECONDS = getEnvVarInt(
  "TERMINATOR_FOREGROUND_COMPLETION_SECONDS",
  60,
);
export const DEFAULT_LINES = getEnvVarInt("TERMINATOR_DEFAULT_LINES", 100);
export const DEFAULT_FOCUS_ON_ACTION = getEnvVarBool(
  "TERMINATOR_DEFAULT_FOCUS_ON_ACTION",
  true,
);
export const DEFAULT_BACKGROUND_EXECUTION = getEnvVarBool(
  "TERMINATOR_DEFAULT_BACKGROUND_EXECUTION",
  false,
); // Added from SDD 3.2.3

// Defines mappings from various raw option keys (case-insensitive) to canonical TerminatorOptions keys.
export const PARAM_ALIASES: { [key: string]: keyof TerminatorOptions } = {
  timeout: "timeout",
  timeoutseconds: "timeout",
  timeout_seconds: "timeout",
  customtimeout: "timeout",
  lines: "lines",
  outputlines: "lines",
  maxlines: "lines",
  projectpath: "project_path",
  project_path: "project_path",
  dir: "project_path",
  directory: "project_path",
  background: "background",
  bg: "background",
  isbackground: "background",
  focus: "focus",
  bringtofront: "focus",
  setfocus: "focus",
  tag: "tag",
  sessiontag: "tag",
  session_tag: "tag",
  command: "command",
  cmd: "command",
  execute: "command",
};

// Defines the order of preference for aliases mapping to the same canonical key.
// For each canonical key, lists its recognized aliases in preferred order.
export const ALIAS_PRIORITY_MAP: {
  [key in keyof TerminatorOptions]?: string[];
} = {
  timeout: ["timeout", "timeoutseconds", "timeout_seconds", "customtimeout"],
  lines: ["lines", "outputlines", "maxlines"],
  project_path: ["project_path", "projectpath", "dir", "directory"],
  background: ["background", "bg", "isbackground"],
  focus: ["focus", "bringtofront", "setfocus"],
  tag: ["tag", "sessiontag", "session_tag"],
  command: ["command", "cmd", "execute"],
};

export function getCanonicalOptions(
  rawOptions: { [key: string]: any } | undefined,
): Partial<TerminatorOptions> {
  const canonical: Partial<TerminatorOptions> = {};
  if (!rawOptions) return {};

  const rawKeys = Object.keys(rawOptions);

  for (const key of Object.keys(ALIAS_PRIORITY_MAP)) {
    const canonicalKey = key as keyof TerminatorOptions;
    const preferredAliases = ALIAS_PRIORITY_MAP[canonicalKey];
    if (!preferredAliases) continue;

    for (const alias of preferredAliases) {
      const matchingRawKey = rawKeys.find(
        (rk) => rk.toLowerCase() === alias.toLowerCase(),
      );
      if (matchingRawKey) {
        if (canonical[canonicalKey] === undefined) {
          // Only take the first matched alias based on priority
          canonical[canonicalKey] = rawOptions[matchingRawKey];
          debugLog(
            `Lenient mapping: used raw key '${matchingRawKey}' for canonical '${canonicalKey}' with value:`,
            rawOptions[matchingRawKey],
          );
        } else {
          debugLog(
            `Lenient mapping: ignored additional raw key '${matchingRawKey}' for canonical '${canonicalKey}' as it was already set.`,
          );
        }
      }
    }
  }

  // Log any unrecognized parameters
  for (const rawKey of rawKeys) {
    let recognized = false;
    for (const key of Object.keys(ALIAS_PRIORITY_MAP)) {
      const canonicalKey = key as keyof TerminatorOptions;
      const preferredAliases = ALIAS_PRIORITY_MAP[canonicalKey];
      if (
        preferredAliases &&
        preferredAliases.some(
          (alias) => alias.toLowerCase() === rawKey.toLowerCase(),
        )
      ) {
        recognized = true;
        break;
      }
    }
    if (!recognized) {
      debugLog(
        `Ignoring unknown parameter: '${rawKey}' with value:`,
        rawOptions[rawKey],
      );
    }
  }
  return canonical;
}
