import { execa } from "execa";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, "../..");
const SWIFT_CLI_PATH = path.join(PROJECT_ROOT, "bin", "terminator");

// Check if we can actually automate Terminal
let terminalAutomationAvailable: boolean | null = null;

export async function isTerminalAutomationAvailable(): Promise<boolean> {
  if (terminalAutomationAvailable !== null) {
    return terminalAutomationAvailable;
  }

  try {
    // Try a simple sessions command to see if AppleScript works
    const result = await execa(
      SWIFT_CLI_PATH,
      ["sessions", "--terminal-app", "terminal"],
      {
        reject: false,
        env: {
          ...process.env,
          TERMINATOR_SKIP_RESPONSIBILITY: "1",
        },
      },
    );

    // If we get exit code 0, automation works
    // If we get exit code 3 (AppleScript error), it doesn't
    terminalAutomationAvailable = result.exitCode === 0;
    return terminalAutomationAvailable;
  } catch {
    terminalAutomationAvailable = false;
    return false;
  }
}

// Helper to run Swift CLI commands
export async function runTerminator(args: string[]) {
  const result = await execa(SWIFT_CLI_PATH, args, {
    reject: false,
    all: true,
    env: {
      ...process.env,
      TERMINATOR_SKIP_RESPONSIBILITY: "1",
    },
  });
  return {
    stdout: result.stdout,
    stderr: result.stderr,
    exitCode: result.exitCode,
    all: result.all,
  };
}

// Skip test if Terminal automation is not available
export async function skipIfNoAutomation(testFn: () => Promise<void>) {
  const available = await isTerminalAutomationAvailable();
  if (!available) {
    console.log("Skipping test: Terminal automation not available");
    return;
  }
  return testFn();
}
