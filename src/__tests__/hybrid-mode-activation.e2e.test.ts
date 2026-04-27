import { describe, it, expect } from "vitest";
import { execFile } from "child_process";
import { promisify } from "util";
import path from "path";

const execFileAsync = promisify(execFile);

describe("Hybrid Mode E2E Tests", () => {
  const terminalPath = path.join(process.cwd(), "bin", "terminator");

  it("should activate hybrid mode when TERMINATOR_EXPERIMENTAL_AX is set", async () => {
    // Run list command with hybrid mode enabled
    const { stdout, stderr } = await execFileAsync(terminalPath, ["sessions", "--json"], {
      env: {
        ...process.env,
        TERMINATOR_EXPERIMENTAL_AX: "true",
        TERMINATOR_LOG_LEVEL: "debug",
      },
    });

    // Check logs for hybrid mode activation
    expect(stderr).toContain("Instantiating HybridAppleTerminalControl");
    expect(stderr).toContain("TerminalAppController initialized for Terminal using Hybrid");

    // Should still produce valid output
    const sessions = JSON.parse(stdout);
    expect(Array.isArray(sessions)).toBe(true);
  });

  it("should use traditional mode when hybrid flag is not set", async () => {
    // Run list command without hybrid mode
    const { stdout, stderr } = await execFileAsync(terminalPath, ["sessions", "--json"], {
      env: {
        ...process.env,
        TERMINATOR_EXPERIMENTAL_AX: undefined,
        TERMINATOR_USE_HYBRID: undefined,
        TERMINATOR_LOG_LEVEL: "debug",
      },
    });

    // Check logs for traditional mode
    expect(stderr).toContain("Instantiating AppleTerminalControl");
    expect(stderr).toContain("TerminalAppController initialized for Terminal using Traditional");

    // Should still produce valid output
    const sessions = JSON.parse(stdout);
    expect(Array.isArray(sessions)).toBe(true);
  });

  it("should respect individual AX feature flags", async () => {
    // Run with specific AX features enabled
    const { stderr } = await execFileAsync(terminalPath, ["sessions", "--json"], {
      env: {
        ...process.env,
        TERMINATOR_AX_WINDOWS: "true",
        TERMINATOR_AX_FOCUS: "true",
        TERMINATOR_LOG_LEVEL: "debug",
      },
    });

    // Should use hybrid mode with specific features
    expect(stderr).toContain("TerminalAppController initialized for Terminal using Hybrid");
    expect(stderr).toContain(
      "Initialized hybrid controller for Terminal with AX features: windows=true, focus=true",
    );
  });

  it("should handle missing accessibility permissions gracefully", async () => {
    // Run with hybrid mode but potentially without permissions
    const { stdout, stderr } = await execFileAsync(terminalPath, ["sessions", "--json"], {
      env: {
        ...process.env,
        TERMINATOR_EXPERIMENTAL_AX: "true",
        TERMINATOR_LOG_LEVEL: "debug",
      },
    });

    // Should either work or gracefully fall back
    const sessions = JSON.parse(stdout);
    expect(Array.isArray(sessions)).toBe(true);

    // Check for permission warnings if any
    if (stderr.includes("Accessibility permission not granted")) {
      expect(stderr).toContain("Hybrid mode features will be limited");
    }
  });
});
