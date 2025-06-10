# Terminator MCP: I'll be back... with your terminal output! 🤖

![Terminator Logo](https://raw.githubusercontent.com/steipete/Terminator/main/assets/logo.png)

[![npm version](https://badge.fury.io/js/%40steipete%2Fterminator-mcp.svg)](https://www.npmjs.com/package/@steipete/terminator-mcp)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://www.apple.com/macos/)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18.0.0-brightgreen.svg)](https://nodejs.org/)

Terminator is an `npx`-installable Model Context Protocol (MCP) plugin designed to provide AI agents with robust, simplified, and intelligent control over macOS terminal sessions. It uses a Swift-based command-line interface (CLI) internally to interact with terminal applications like Apple Terminal, iTerm2, and Ghosty.

## 🚀 Installation

### Requirements

- **macOS 14.0+** (Sonoma or later)
- **Node.js 18.0+**

### 🕯️ Quick Installation

Add Terminator to your Claude Desktop configuration:

```json
{
  "mcpServers": {
    "terminator": {
      "command": "npx",
      "args": [
        "-y",
        "@steipete/terminator-mcp@beta"
      ],
      "env": {
        "TERMINATOR_APP": "Terminal"
      }
    }
  }
}
```

1. Open Claude Desktop settings
2. Navigate to "Developer" → "Edit Config"
3. Add the configuration above
4. Restart Claude Desktop

That's it! Terminator is now ready to manage your terminal sessions! 🎯

### 🔧 Configuration Options

Customize Terminator's behavior with environment variables:

```json
{
  "mcpServers": {
    "terminator": {
      "command": "npx",
      "args": [
        "-y",
        "@steipete/terminator-mcp@beta"
      ],
      "env": {
        "TERMINATOR_APP": "iTerm",
        "TERMINATOR_LOG_LEVEL": "debug",
        "TERMINATOR_LOG_DIR": "~/Library/Logs/terminator-mcp",
        "TERMINATOR_WINDOW_GROUPING": "smart",
        "TERMINATOR_DEFAULT_LINES": "100",
        "TERMINATOR_DEFAULT_FOCUS_ON_ACTION": "true"
      }
    }
  }
}
```

### 📦 Alternative Installation Methods

#### From npm Registry

```bash
npm install -g @steipete/terminator-mcp
```

Then configure your MCP client:

```json
{
  "mcpServers": {
    "terminator": {
      "command": "terminator-mcp",
      "args": [],
      "env": {
        "TERMINATOR_APP": "Terminal"
      }
    }
  }
}
```

#### From Source

```bash
# Clone the repository
git clone https://github.com/steipete/terminator.git
cd terminator

# Install dependencies
npm install

# Build TypeScript
npm run build

# Build Swift CLI
cd cli
swift build -c release
cd ..

# Copy the binary
cp cli/.build/release/terminator bin/

# Optional: Link globally
npm link
```

For local development configuration:

```json
{
  "mcpServers": {
    "terminator": {
      "command": "node",
      "args": ["/Users/steipete/Projects/Terminator/dist/index.js"],
      "env": {
        "MCP_SERVER_VIA_STDIO": "true",
        "TERMINATOR_LOG_LEVEL": "debug",
        "TERMINATOR_LOG_FILE": "/tmp/terminator.log"
      }
    }
  }
}
```

Replace `/Users/steipete/Projects/Terminator` with your actual project path.

## Functionality

The core functionality is exposed via the `terminator.execute` MCP tool. This tool allows an AI agent to perform actions such as:

*   **`execute`**: Execute a shell command in a managed terminal session.
*   **`read`**: Read output from an existing session.
*   **`sessions`**: List all active Terminator-managed sessions.
*   **`info`**: Get information about Terminator (version, configuration, sessions).
*   **`focus`**: Bring a specific session's terminal window/tab to the foreground.
*   **`kill`**: Terminate the process running in a specific session.

### `terminator.execute` MCP Tool

**Overall Description (Dynamically Constructed Example):**

"Manages macOS terminal sessions using the `iTerm` application. Ideal for running commands that might be long-running or could hang, as it isolates them to protect your workflow and allows for faster interaction. The session screen is automatically cleared before executing a new command or after a process is killed. Use this to execute shell commands, retrieve output, and manage terminal processes."

**(Note: The actual terminal application mentioned in the description will depend on your `TERMINATOR_APP` environment variable.)**

**Parameters:**

*   `action: string` (Required): The operation to perform. Enum: `"execute"`, `"read"`, `"sessions"`, `"info"`, `"focus"`, `"kill"`. Default: `"execute"`.
*   `project_path: string` (Required): Absolute path to the project directory. This is used to uniquely identify sessions and can influence window/tab grouping behavior.
*   `tag?: string`: An optional unique identifier for the session within the context of a `project_path`. If omitted, a tag may be derived from the `project_path` or other factors. Primarily used with `execute`, `read`, `kill`, `focus`. Can be used to filter `sessions`.
*   `command?: string`: (Required for `action: "execute"`) The shell command to execute. Example: `"npm run dev"`.
*   `background?: boolean`: (For `action: "execute"`, default: `false`) If `true`, the command is considered long-running (e.g., a server); the tool returns quickly after starting it. If `false`, the tool waits for the command to complete (or timeout).
*   `lines?: number`: (For `action: "execute"`, `"read"`, default: `100`) Maximum number of recent output lines to return.
*   `timeout?: number`: (For `action: "execute"`, in seconds) Overrides the default timeout. For `background: true`, this is the startup timeout. For `background: false`, this is the completion timeout.
*   `focus?: boolean`: (For `action: "execute"`, `"read"`, `"kill"`, `"focus"`, default: `true`) If `true`, `terminator` will attempt to bring the terminal application to the foreground and focus the relevant session. For `action: "focus"`, this is implicitly `true`.

**Returns:** `Promise<{ success: boolean, message: string, data?: any }>` (The `data` field may contain action-specific information, e.g., output for `read` or `execute`)

## Configuration (Environment Variables)

The `terminator` Swift CLI (and by extension, this NPM package) can be configured using the following environment variables. CLI flags passed to the Swift CLI directly take precedence over these.

*   **`TERMINATOR_APP`**: The terminal application to use.
    *   Examples: `"Terminal"`, `"iTerm"`, `"Ghosty"`
    *   Default: `"Terminal"`
    *   Note: The specified application must be installed and scriptable.

*   **`TERMINATOR_LOG_LEVEL`**: Logging verbosity for the Swift CLI.
    *   Values: `"debug"`, `"info"`, `"warn"`, `"error"`, `"fatal"` (case-insensitive)
    *   Default: `"info"`

*   **`TERMINATOR_LOG_FILE`**: Custom path for the log file.
    *   Example: `/tmp/terminator.log` or `~/custom-terminator.log`
    *   If not set, defaults to `~/Library/Logs/terminator-mcp/terminator.log`
    *   Fallback: `/tmp/terminator-mcp/terminator.log` if default location is not writable

*   **`TERMINATOR_LOG_DIR`**: Directory where the Swift CLI will write its log files.
    *   Default: `~/Library/Logs/terminator-mcp/`
    *   Fallback: A `terminator-mcp` subdirectory within the system's temporary directory (e.g., `/var/folders/.../terminator-mcp/`)

*   **`TERMINATOR_WINDOW_GROUPING`**: Strategy for how new sessions group into windows/tabs.
    *   `"off"`: Always aim for a new window unless an exact session (project+tag) already exists.
    *   `"project"`: Group tabs into an existing window associated with the same `project_path`. If no such window, creates a new one.
    *   `"smart"`: (Default) Tries to find an existing window for the `project_path`. If none, tries to find *any* Terminator-managed window. Otherwise, creates a new window. (See SDD for full logic).
    *   Default: `"smart"`

*   **`TERMINATOR_DEFAULT_LINES`**: Default maximum number of output lines to return for `execute` and `read` actions if not specified in the call.
    *   Default: `100`

*   **`TERMINATOR_BACKGROUND_STARTUP_SECONDS`**: Default timeout (in seconds) for commands run with `background: true` to produce initial output before the `execute` action returns.
    *   Default: `5`

*   **`TERMINATOR_FOREGROUND_COMPLETION_SECONDS`**: Default timeout (in seconds) for commands run with `background: false` to complete.
    *   Default: `60`

*   **`TERMINATOR_DEFAULT_FOCUS_ON_ACTION`**: Default behavior for whether to focus the terminal on actions like `execute`, `read`, `kill`, `focus`.
    *   Values: `"true"`, `"false"` (case-insensitive, also accepts `"1"`, `"0"`, `"yes"`, `"no"`, etc.)
    *   Default: `"true"`

*   **`TERMINATOR_SIGINT_WAIT_SECONDS`**: Time (in seconds) the `kill` subcommand waits after sending SIGINT before escalating (during process termination or when `execute` stops a busy process).
    *   Default: `2`

*   **`TERMINATOR_SIGTERM_WAIT_SECONDS`**: Time (in seconds) the `kill` subcommand waits after sending SIGTERM before escalating to SIGKILL.
    *   Default: `2`

## Permissions Setup (macOS Automation)

For `terminator` to control terminal applications like Apple Terminal or iTerm2, you need to grant it Automation permissions in macOS.

1.  The first time `terminator` attempts to control an application (e.g., Terminal.app), macOS will prompt you to allow this. You **must click "OK"**. 
    *   *(Screenshot of typical permission dialog would go here)*
2.  If you accidentally click "Don't Allow" or want to manage these permissions:
    *   Open **System Settings**. 
    *   Go to **Privacy & Security** -> **Automation**.
    *   Find the application that *ran* `terminator` (this might be your IDE, e.g., "Cursor", or "Terminal" itself if you ran a test script from there).
    *   Ensure it has a checkbox enabled for the target terminal application (e.g., "Terminal", "iTerm").
    *   *(Screenshot of Automation settings panel would go here)*

To reset permissions for testing or troubleshooting (this will cause macOS to prompt again):

```bash
# Reset AppleEvents permissions for Terminal
tccutil reset AppleEvents com.apple.Terminal

# Reset AppleEvents permissions for iTerm2 (bundle ID might vary slightly)
tccutil reset AppleEvents com.googlecode.iterm2

# If terminator is run via an IDE like Cursor, you might also need to reset for that IDE:
# tccutil reset AppleEvents com.example.cursor # Replace with actual bundle ID
```

**It is strongly recommended to grant permissions when prompted.**

## Verification

Once installed and permissions are set up (if needed for your chosen `TERMINATOR_APP`), you can verify the setup. The exact method depends on how you're integrating/testing the MCP plugin.

If your MCP host allows sending raw commands, try:

```json
{
  "tool_name": "terminator.execute",
  "inputs": {
    "action": "info"
  }
}
```

This should return information about `terminator`, including its version, the configured terminal app, and any active sessions.

To test command execution (ensure `TERMINATOR_APP` is set, e.g., to `Terminal`):

```json
{
  "tool_name": "terminator.execute",
  "inputs": {
    "action": "execute",
    "options": {
      "tag": "test-echo",
      "command": "echo \"Hello from Terminator MCP!\" && sleep 2",
      "background": false,
      "focus": true
    }
  }
}
```

You should see your configured terminal application open/focus, execute the echo, and the MCP call should return a success message with the output.

## Troubleshooting

*   **"Swift CLI Code null" or Process Crashes:** This usually indicates:
    *   **Missing Automation Permissions:** The most common cause. Grant automation permissions in **System Settings → Privacy & Security → Automation**. Look for Claude Desktop (or your MCP client) and ensure it can control Terminal/iTerm.
    *   **First Run:** The first time you use Terminator, macOS will prompt for automation permissions. You must click "OK" to allow.
    *   **Terminal Window Issues:** If you see AppleScript errors about window IDs, try closing all Terminal windows and letting Terminator create fresh ones.
    
*   **Permissions Issues:** Double-check **System Settings → Privacy & Security → Automation**. Ensure the calling application (Claude Desktop, VS Code, etc.) has permission to control the `TERMINATOR_APP`.

*   **`TERMINATOR_APP` not found/supported:** Ensure the application specified in `TERMINATOR_APP` is installed and is one of the supported terminals (Apple Terminal, iTerm2, Ghosty). The CLI will error if it cannot interact with the specified app.

*   **Log Files:** The Swift CLI component logs to files. Default locations:
    *   Primary: `~/Library/Logs/terminator-mcp/terminator.log`
    *   Fallback: `/tmp/terminator-mcp/terminator.log`
    *   Custom: Set `TERMINATOR_LOG_FILE` environment variable
    *   Check these logs for detailed error messages or debug information (set `TERMINATOR_LOG_LEVEL="debug"` for more verbosity).

*   **Swift CLI not executable:** The `postinstall` script for this NPM package attempts to `chmod +x bin/terminator`. If this failed, you might need to do it manually.

## Privacy and Security

*   Commands executed by `terminator` run with the same privileges as the user running the MCP host application.
*   Be aware that shell commands and file paths (which could be considered Personally Identifiable Information - PII) might be logged by the Swift CLI if the `TERMINATOR_LOG_LEVEL` is set to `debug`. Consult the Swift CLI's `README.md` (once available) for more details on its logging behavior.

## AI Tool Overview: `terminator.execute`

| `action` (default: `execute`) | Parameters                                                                                                   |
| :---------------------------- | :----------------------------------------------------------------------------------------------------------- |
| `execute`                     | `project_path`, `command`, `tag?`, `background?`, `lines?`, `timeout?`, `focus?`                             |
| `read`                        | `project_path`, `tag?`, `lines?`, `focus?`                                                                     |
| `sessions`                    | `project_path?`, `tag?` (can list all if both omitted, or filter)                                           |
| `info`                     | (No specific parameters beyond global ones if applicable; `project_path` and `tag` are generally not used) |
| `focus`                    | `project_path`, `tag?` (`focus` is implicitly true)                                                          |
| `kill`                     | `project_path`, `tag?`, `focus?`                                                                               |

* `?` denotes optional.
* `project_path` is always required.
* Defaults for `lines`, `timeout`, `focus`, and `background` are taken from environment variables if not specified in the call. 