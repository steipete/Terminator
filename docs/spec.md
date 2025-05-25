## Terminator MCP Plugin - Software Design Document

**Version:** 1.3
**Date:** May 23, 2025
**Primary Maintainer:** `@steipete`
**Context Prompt Summary (Original Request Essence & V1.3 Refinements):**
The goal is an MCP plugin (`terminator`) providing a terminal utility. Originally AppleScript-based, it's to be re-implemented with a Swift CLI binary wrapped in a Node.js MCP package. Key requirements include: clear tool description for ML model use, similar feature set to the old script but with smarter CLI parameters, NPX installation, configurable terminal app (Apple Terminal default, supporting iTerm, Ghosty), logging to a temporary directory (not stdout), an info block on first significant use, session tracking capabilities, and robust testing focused on the Swift CLI. The project emphasizes minimizing user focus disruption and providing a simple, reliable interface for AI agents.
**V1.3 Refinements:** The `action` parameter for the AI tool is now optional, defaulting to `"execute"`. The action name `"exec"` has been changed to `"execute"` throughout for clarity for AI agents. This SDD version incorporates extensive detailing to proactively address implementation ambiguities and ensure all rules and behaviors are explicitly defined.

**1. Overview**

**1.1. Purpose & Scope**
Terminator is an `npx`-installable Model Context Protocol (MCP) plugin designed to provide AI agents with robust, simplified, and intelligent control over macOS terminal sessions. Its primary goal is to allow AI assistants to execute shell commands, retrieve output, and manage terminal processes in a way that:
    *   Prevents hanging or long-running commands from breaking the AI's primary execution loop.
    *   Minimizes user focus disruption, a core design principle.
    *   Offers a clear, consistent, and minimal interface to the AI agent.
    *   Leverages existing terminal applications (Apple Terminal, iTerm2, Ghosty) as the display and execution environment.

**1.2. Goals**
    *   **Reliability:** Stable operation, especially for process control and session management. Consistent behavior across supported terminal applications.
    *   **Simplicity for AI:** Minimal set of actions and options for the AI agent; clear, actionable feedback. The primary action, `execute`, is now the default if no action is specified.
    *   **User Experience:** Minimize focus stealing; respect user's terminal environment and preferences. Provide clear feedback on operations.
    *   **Robustness:** Handle variations in AI input gracefully, including lenient parsing of options.
    *   **Configurability (User):** Allow users to set sensible defaults for their environment via environment variables, which are then reflected in the AI tool's description.

**1.3. Non-Goals (for V1)**
    *   Building a custom terminal emulator.
    *   Supporting operating systems other than macOS.
    *   Providing interactive STDIO sessions for the AI with processes in the terminal (i.e., AI cannot respond to prompts like password requests within a `terminator`-managed session).
    *   YAML configuration file support (configuration via environment variables and CLI flags only for V1).
    *   Advanced features like session templating, complex real-time output streaming (beyond initial output for background tasks), or cloud storage integration.
    *   Shell-agnostic input: The `command` is passed to the user's default shell as configured in the terminal application. `terminator` does not attempt to interpret or transpile commands between shells.

**2. System Architecture**

Terminator consists of two main components:
    1.  **Node.js MCP Wrapper (`@steipete/terminator-mcp`):** The NPM package that implements the MCP server logic. It interfaces with the AI agent/MCP host and orchestrates calls to the Swift CLI.
    2.  **Swift CLI (`terminator`):** A native macOS command-line executable bundled within the NPM package. It performs all direct interactions with the macOS system and terminal applications.

**Diagram (Conceptual):**
```
+---------------------+     MCP      +-------------------------+     Internal     +----------------------+
| AI Agent / MCP Host | <----------> | Node.js Wrapper         | <--------------> | Swift CLI            |
| (e.g., Cursor, IDE) |  (JSON-RPC)  | (@steipete/terminator-mcp)|  (spawn process,  | (terminator binary)  |
+---------------------+              +-------------------------+   stdout/stderr)   +----------------------+
                                           |                                             |
                                           |                                             v
                                           +-------------------------------------> macOS System APIs
                                                                                       (Process mgmt, FS)
                                                                                        AppleScript
                                                                                        (to Terminal Apps)
```
*Note: `stdin` to Swift CLI is not used for V1. Communication is via CLI arguments and environment variables for input, and `stdout` (for JSON or raw output) / `stderr` (for errors) / exit codes for output.*

**3. Detailed Component Specifications**

**3.1. NPM Package: `@steipete/terminator-mcp`**

    *   **3.1.1. Package Details:**
        *   **Name:** `@steipete/terminator-mcp`
        *   **Initial Version:** `0.1.0`
        *   **Maintainer:** `@steipete`
        *   **License:** MIT (or as specified by `@steipete`)
        *   **SDK Dependency:** `modelcontextprotocol/typescript-sdk` (version to be specified, e.g., `^0.5.0`)
        *   **Bundled Executable:** Includes the pre-compiled universal macOS binary of the `terminator` Swift CLI, located at `swift-bin/terminator` within the package. This path will be resolved dynamically using `path.join(__dirname, '..', 'swift-bin', 'terminator')` assuming the JS files are in a `dist` or `lib` subdirectory.

    *   **3.1.2. Node.js Wrapper Responsibilities:**
        *   **MCP Tool Registration:** Registers a single tool, `terminator.execute`, with the MCP host. (Note: The tool name is `terminator.execute`, aligning with the default action, but it handles *all* actions like `list`, `kill`, etc., via its `action` parameter).
        *   **Dynamic Tool Description Construction:**
            *   On initialization, the wrapper reads all relevant `TERMINATOR_*` environment variables (listed in Section 3.2.3).
            *   These read values are used to populate the *default values* for corresponding parameters (`lines`, `timeout`, `focus`, `background`) in the JSON schema of the `terminator.execute` tool presented to the AI.
            *   The resolved `TERMINATOR_APP` name will be incorporated into the overall tool description string.
            *   A suffix indicating the Terminator MCP version and the resolved `TERMINATOR_APP` will be appended to the main tool description (e.g., "...manage terminal processes. \nTerminator MCP [VERSION] using [APP_NAME]").
            *   The `TERMINATOR_*` environment variables **do not alter the structural definition** (e.g., adding/removing parameters) of the tool schema; they only affect the default values and descriptive text.
        *   **Parameter Parsing & Validation (AI Input):**
            *   **Action Defaulting:** If the `action` parameter is omitted by the AI, it defaults to `\"execute\"`.
            *   **`project_path` Mandate:** The `project_path` parameter is mandatory.
            *   **Canonical Keys:** All option keys documented and presented to the AI in the tool schema are strictly `snake_case` or `camelCase` as defined (e.g., `project_path`, `timeout`).
            *   **Lenient Key Matching (Internal):**
                *   The wrapper maintains a predefined, ordered map of common aliases to their canonical `camelCase` form. Example:
                    ```typescript
                    const aliasMap = new Map<string, string>([
                        ['timeout', 'timeout'], // Canonical preferred
                        ['timeoutseconds', 'timeout'],
                        ['timeout_seconds', 'timeout'],
                        ['lines', 'lines'],
                        ['maxlines', 'lines'],
                        ['max_lines', 'lines'],
                        // ... other aliases
                    ]);
                    ```
                *   When parsing AI-provided `options`, the wrapper iterates through the keys provided by the AI. For each AI-provided key, it checks against the `aliasMap`.
                *   If multiple AI-provided keys map to the same canonical option (e.g., `options: { timeout: 10, TimeoutSeconds: 20 }`), the value associated with the AI-provided key that matches an alias *earlier in the `aliasMap`'s definition order* will take precedence. If an exact canonical key is provided, it usually has the highest precedence (should be listed first in the map entry for that canonical key).
                *   A debug message will be logged if multiple aliases for the same canonical option are provided, indicating which one was chosen.
            *   **Type Coercion (Strict for `options` values):**
                *   `command`: Must be a string.
                *   `project_path`: Must be a string.
                *   `tag`: Must be a string.
                *   `background`: Strings `"true"`, `"1"`, `"t"`, `"yes"`, `"on"` (case-insensitive) coerce to `true`. Strings `"false"`, `"0"`, `"f"`, `"no"`, `"off"` (case-insensitive) coerce to `false`. Other types/values result in an error if the parameter is provided with an uncoercible value. If `background` is not provided, its default is used.
                *   `lines`: Strings representing integers (e.g., `"50"`) coerce to `number`. Floating point strings (e.g. `"50.5"`) will be floored. Non-numeric strings result in an error if the parameter is provided. If `lines` is not provided, its default is used.
                *   `timeout`: Strings representing integers (e.g., `"60"`) coerce to `number`. Floating point strings will be floored. Non-numeric strings result in an error if the parameter is provided. If `timeout` is not provided, its default is used.
                *   `focus`: Same coercion rules as `background`.
                *   **Coercion Failure:** If coercion fails for any explicitly provided parameter value, an error is returned to the AI detailing the problematic parameter and value. Defaults are only used if the parameter is *omitted*, not if it's provided with an invalid value.
            *   **Ignoring Unknown Parameters:** Extra, unrecognized parameters within `options` will be ignored, and a debug message logged (e.g., "Ignoring unknown option 'fooBar' in terminator.execute call.").
            *   **Input Size:** For V1, reasonable input sizes for strings like `command` (e.g., < 16KB) are assumed. Extremely large inputs may lead to OS-level errors during process spawning; the wrapper does not impose its own limits but may fail if `child_process.spawn` fails due to argument length.
        *   **`effectiveProjectPath` Resolution (Strict Order of Priority):**
            1.  Explicit `project_path` from AI call (mandatory). Must be an absolute path. If relative, an error is returned.
            2.  Path from MCP `ctx.requestContext.roots`: (No longer primary for `effectiveProjectPath` as `project_path` is mandatory from AI, but could be a fallback or cross-reference if needed for other context in the future, though not for `effectiveProjectPath` itself).
            3.  Predefined list of environment variables (checked in this order): (No longer primary for `effectiveProjectPath`)
                a.  `CURSOR_ACTIVE_PROJECT_ROOT`
                b.  `VSCODE_CWD` (commonly set by VS Code integrated terminals, may reflect project root)
                c.  `TERMINATOR_MCP_PROJECT_ROOT` (a user-configurable override)
            4.  The `project_path` provided by the AI is the sole source for `effectiveProjectPath`. If it's not a valid, absolute path, an error is returned.
        *   **Default `tag` Resolution:**
            *   If `options.tag` (now a root-level `tag` parameter) is omitted by the AI:
                1.  The default tag will be the last path component (basename) of the mandatory `effectiveProjectPath` (derived from the AI-provided `project_path`).
                2.  If the last component is empty (e.g., path ends in `/`), the second-to-last component will be used.
                3.  If `effectiveProjectPath` is `/` or resolution yields an empty string (e.g. path is `///`), a fixed default tag `"_root_project_"` will be used.
                4.  **Sanitization Rule for Derived Tag:** The derived tag is sanitized to ensure it is safe for internal use and display:
                    *   Replaced non-alphanumeric characters (excluding hyphen `-` and underscore `_`) with an underscore `_`.
                    *   Truncated to a maximum of 64 characters.
                    *   If the result is empty after sanitization (e.g., input was `///`), use `"_default_tag_"`.
                    *   Example Regex for allowed characters (applied after basename extraction): `/[^a-zA-Z0-9_-]/g` (replace with `_`).
            *   If `options.tag` is omitted and `effectiveProjectPath` cannot be determined (this should not happen as `project_path` is mandatory), and the `action` requires a `tag` (e.g., `execute`, `read`, `kill`, `focus`), an error will be returned to the AI ("Cannot determine a session tag. Please provide a 'tag' or ensure a project context is available."). `list` and `info` can operate without a tag if the Swift CLI supports it (though usually a tag is derived).
        *   **Swift CLI (`terminator`) Invocation:**
            *   Constructs the appropriate `terminator` subcommand (e.g., `execute`, `list`) and arguments (e.g., `--project_path`, `--tag`, `--lines`). All Swift CLI arguments will be `kebab-case`.
            *   Spawns the bundled `terminator` Swift binary as a child process using `child_process.spawn`.
            *   **Environment Variable Forwarding:** The Node.js wrapper will *selectively* pass only the known `TERMINATOR_*` environment variables (listed in Section 3.2.3) that are present in its own environment to the Swift CLI process. It does not pass its entire `process.env`.
            *   Includes an internal, non-configurable timeout for the Swift CLI process itself. This timeout will be `MAX(TERMINATOR_FOREGROUND_COMPLETION_SECONDS, TERMINATOR_BACKGROUND_STARTUP_SECONDS) + 60 seconds` (a fixed 60-second buffer). If this wrapper-level timeout is hit, the Swift CLI process will be killed using `SIGKILL`, and an error "Terminator Swift CLI unresponsive and was terminated." returned to the AI.
        *   **Output Handling from Swift CLI:**
            *   For `terminator list` and `terminator info` subcommands, the wrapper *always* appends `--json` when invoking the Swift CLI. The `stdout` (JSON string) from the Swift CLI is then parsed by the wrapper.
            *   For `terminator execute` and `terminator read` subcommands, the `stdout` is treated as raw text output from the command/session.
            *   The wrapper formats results into the `message` field of the `Promise<{ success: boolean, message: string }>` structure returned to the AI, according to the rules in Section 3.1.4.
        *   **Error Handling & Swift CLI Crash Detection:**
            *   Captures `stdout`, `stderr`, and exit code from the Swift CLI.
            *   If the Swift CLI exits with a non-zero code (see Section 3.2.8 for codes), its `stderr` output (if any) is used as the primary content for the error message to the AI. If `stderr` is empty, a generic message based on the exit code is used.
            *   The `child_process` event `on('error')` (for spawn errors like binary not found, permissions) is handled.
            *   If the `terminator` binary is not found at the expected path `swift-bin/terminator` during a call, the wrapper returns a critical error "Terminator Swift CLI binary not found. Please check installation."
        *   **Cancellation of AI Request:** If the MCP host signals cancellation of the request (e.g., via `AbortSignal`) while the Node.js wrapper is awaiting the Swift CLI:
            1.  The wrapper will attempt to `SIGKILL` the spawned Swift CLI child process.
            2.  It will then return a specific error to the MCP host indicating cancellation, e.g., `{ success: false, message: "Terminator action cancelled by request." }`.

    *   **3.1.4. AI-Facing Message Formatting Rules (for `message` field in return object):**
        *   **Success General:** "Terminator: Action '[actionName]' completed successfully for session '[displayTag]'."
        *   **`execute` Success (Foreground):** "Terminator: Command completed in session '[displayTag]'. Output:\n[captured stdout/stderr up to 'lines' limit]"
        *   **`execute` Success (Background Start):** "Terminator: Command started in background in session '[displayTag]'. Initial output (up to 'lines' limit):\n[captured stdout/stderr]"
        *   **`execute` Timeout:** "Terminator: Command timed out after X seconds in session '[displayTag]'. Output may be incomplete. Output:\n[captured stdout/stderr up to 'lines' limit]"
        *   **`read` Success:** "Terminator: Content from session '[displayTag]':\n[captured scrollback up to 'lines' limit]"
        *   **`list` Success (Example):** "Terminator: Found 2 sessions.\n1. 🤖💥 MyProject / api (Busy)\n2. 🤖💥 ui_tests (Idle)" (Session details derived from Swift CLI JSON output). If no sessions: "Terminator: No active sessions found."
        *   **`info` Success (Example):** "Terminator v0.1.0. Config: App=iTerm, Grouping=smart, LogLevel=info. Active Sessions:\n1. 🤖💥 MyProject / api (Busy)" (Or "No active sessions.") (Details from Swift CLI JSON).
        *   **`kill` Success:** "Terminator: Process in session '[displayTag]' successfully terminated."
        *   **`focus` Success:** "Terminator: Session '[displayTag]' is now focused."
        *   **Error (General):** "Terminator Error: [Descriptive message from Swift CLI stderr or wrapper validation/error condition]."
        *   **Error (Session Not Found):** "Terminator Error: Session with project '[projectIdentifierOrNone]' and tag '[tag]' not found."
        *   `[displayTag]` is the sanitized tag, potentially prefixed with a project identifier if available (e.g., "ProjectName / task_tag").

    *   **3.1.5. MCP Tool Definition: `terminator.execute` (Presented to AI Agent)**
        *   **(Dynamically Constructed) Overall Description:**
            "Manages macOS terminal sessions using the `[Resolved TERMINATOR_APP, e.g., \"iTerm\"]` application. Ideal for running commands, especially those that might be long-running or could hang, as it isolates them to protect your workflow. The session screen is automatically cleared before executing a new command or after a process is killed. Use this to execute shell commands, retrieve output, and manage terminal processes. If 'action' is not specified, it defaults to 'execute'. \nTerminator MCP [SERVER_VERSION] using [Resolved TERMINATOR_APP]"
        *   **Parameters (Schema - Flattened Structure):**
            *   `action?: string`: (Optional, default: `\"execute\"`) The operation to perform: 'execute', 'read', 'list', 'info', 'focus', or 'kill'. Defaults to 'execute'.
                *   Enum: `\"execute\"`, `\"read\"`, `\"list\"`, `\"info\"`, `\"focus\"`, `\"kill\"`.
            *   `project_path: string`: (Mandatory) Absolute path to the project directory.
            *   `tag?: string`: (Optional) A unique identifier for the session (e.g., \"ui-build\", \"api-server\"). If omitted, a tag will be derived from the `project_path`.
            *   `command?: string`: (Optional, primarily for `action: \"execute\"`) The shell command to execute. If `action` is 'execute' and `command` is empty or omitted, the session will be prepared (cleared, focused if applicable), but no new command is run.
            *   `background?: boolean`: (Optional, for `action: \"execute\"`, default: `false`, reflected from `TERMINATOR_DEFAULT_BACKGROUND_EXECUTION` if set, otherwise `false`)
                *   If `true`, command is treated as long-running; `terminator` waits up to the background startup timeout (default: `[Resolved TERMINATOR_BACKGROUND_STARTUP_SECONDS, e.g., 5]` seconds, see `timeout` option) for initial output, then returns, leaving the command running.
                    *   If `false` (default), command is expected to complete; `terminator` waits up to the foreground completion timeout (default: `[Resolved TERMINATOR_FOREGROUND_COMPLETION_SECONDS, e.g., 60]` seconds, see `timeout` option) for it to finish.
            *   `lines?: number`: (Optional, for `action: \"execute\"`, `\"read\"`, default: `[Resolved TERMINATOR_DEFAULT_LINES, e.g., 100]`) Maximum number of recent output lines (from `stdout` and `stderr` combined for `execute`, or scrollback for `read`) to return.
            *   `timeout?: number`: (Optional, for `action: \"execute\"`, in seconds) Overrides the system's default timeout for this specific call.
                *   If `background: true`, this `timeout` applies to the background startup period.
                *   If `background: false`, this `timeout` applies to the foreground completion period.
                *   If omitted, system defaults (derived from `TERMINATOR_BACKGROUND_STARTUP_SECONDS` or `TERMINATOR_FOREGROUND_COMPLETION_SECONDS`) are used based on the `background` flag.
            *   `focus?: boolean`: (Optional, for actions `execute`, `read`, `kill`, `focus`, default: `[Resolved TERMINATOR_DEFAULT_FOCUS_ON_ACTION, e.g., true]`) If true, `terminator` will attempt to bring the terminal application to the foreground and focus the relevant session's tab/window.
        *   **Returns:** `Promise<{ success: boolean, message: string }>`. The `message` field contains human-readable output or error details.

**3.2. Swift CLI (Binary Name: `terminator`)**

    *   **3.2.1. Technology & Build:**
        *   **Language:** Swift 6 (or latest stable Swift version at time of implementation).
        *   **Target macOS:** 14.0+ (Sonoma). APIs available on macOS 14 will be prioritized. macOS 15-specific APIs will only be used if a critical feature absolutely requires them and the benefit outweighs the compatibility reduction, in which case macOS 15 would become the minimum.
        *   **CLI Framework:** `swift-argument-parser`
        *   **Testing Framework:** `XCTest`
        *   **Compilation:** Universal macOS binary (arm64 & x86_64).
        *   **Dependencies:** Swift standard library, Foundation, AppKit, `swift-argument-parser`. No external binary dependencies beyond system tools like `ps`.

    *   **3.2.2. Responsibilities:**
        *   Handles all direct interactions with macOS (process management via `Process`, file system) and supported terminal applications (via AppleScript).
        *   Implements robust session management logic (identification, creation, reuse).
        *   Manages process execution, output capture (from TTY), and process control (termination).
        *   Parses its command-line arguments (subcommands, options, flags) using `swift-argument-parser`.
        *   Loads and resolves its configuration from environment variables and CLI flags.

    *   **3.2.3. Configuration (V1 - Environment Variables & CLI Flags Only):**
        *   **Priority of Configuration Sources (Highest to Lowest):**
            1.  Swift CLI Flags (e.g., `--terminal-app iTerm`)
            2.  Environment Variables (e.g., `TERMINATOR_APP=iTerm`)
            3.  Built-in Default Values (hardcoded in Swift).
        *   **Environment Variables (Prefix `TERMINATOR_`):** All are parsed by the Swift CLI.
            1.  `APP`: String. Name of the terminal application (e.g., `"Terminal"`, `"iTerm"`, `"Ghosty"`). Default: `"Terminal"`. Value parsed case-insensitively.
                *   **Validation:** Swift CLI checks if the specified application ID (e.g., `com.apple.Terminal`, `com.googlecode.iterm2`, `com.jin.Ghosty`) exists and is launchable. If `Ghosty` is specified, a minimal AppleScript interaction (e.g., `get version`) is attempted. If it fails (e.g., app not installed, scripting disabled), CLI errors out with code 2.
            2.  `LOG_LEVEL`: String. Logging verbosity (`"debug"`, `"info"`, `"warn"`, `"error"`, `"none"`). Default: `"info"`. Value parsed case-insensitively.
            3.  `LOG_DIR`: String. Path to the directory for log files. Default: `~/Library/Logs/terminator-mcp/`. `~` is expanded to the user's home directory.
                *   **Fallback:** If the default path `~/Library/Logs/terminator-mcp/` cannot be created or is not writable, and `TERMINATOR_LOG_DIR` is not explicitly set to something else, the CLI will attempt to use `NSTemporaryDirectory()/terminator-mcp/`. If `TERMINATOR_LOG_DIR` is explicitly set to the special value `"SYSTEM_TEMP"`, it will also use `NSTemporaryDirectory()/terminator-mcp/`.
            4.  `WINDOW_GROUPING`: String. Tab grouping strategy (`"off"`, `"project"`, `"smart"`). Default: `"smart"`. Value parsed case-insensitively.
                *   `"off"`: Always aims for a new window unless an *exact* session (identified by project hash and tag) already exists in *any* window. If it exists, that tab is reused. Otherwise, new window, new tab.
                *   `"project"`: Aims to group tabs into an existing window already associated with the *same* `effectiveProjectPath` (matched by project hash in tab title). If multiple such windows exist, the one with the most Terminator tabs is chosen. If no such window exists, a new window is created.
                *   `"smart"`:
                    1.  If `project_path` is provided by AI (which it will be, as it's mandatory): Try to find an existing window associated with this *exact* `project_path` (matched by project hash). If found, use it. If multiple, prefer one with more Terminator tabs.
                    2.  Else (no `project_path` or no existing window specifically for it - this case should not occur due to mandatory `project_path`): Try to find *any* existing window containing *any* Terminator-managed tab. Prioritize windows with more Terminator tabs.
                    3.  Else (no Terminator-managed tabs found anywhere): Create a new window.
            5.  `DEFAULT_LINES`: Integer. Default number of output lines to capture and return. Default: `100`. Must be >= 0.
            6.  `BACKGROUND_STARTUP_SECONDS`: Integer. Default timeout in seconds for `execution-mode: background` to wait for initial output. Default: `5`. Must be >= 1.
            7.  `FOREGROUND_COMPLETION_SECONDS`: Integer. Default timeout in seconds for `execution-mode: foreground` to wait for command completion. Default: `60`. Must be >= 1.
            8.  `DEFAULT_FOCUS_ON_ACTION`: Boolean-like String (`"true"`, `"false"`, `"1"`, `"0"`, etc.). Default: `"true"`. Value parsed case-insensitively.
            9.  `SIGINT_WAIT_SECONDS`: Integer. Time in seconds to wait after sending SIGINT during the `kill` subcommand's escalation sequence before proceeding to SIGTERM. Default: `2`. Must be >= 0.
            10. `SIGTERM_WAIT_SECONDS`: Integer. Time in seconds to wait after sending SIGTERM during the `kill` subcommand's escalation sequence before proceeding to SIGKILL. Default: `2`. Must be >= 0.
            11. `DEFAULT_BACKGROUND_EXECUTION`: Boolean-like String. Default for the `background` option in the `execute` action if not specified by the AI. Default: `"false"`.
        *   **Global CLI Flags (for `terminator` binary, using `swift-argument-parser` conventions):**
            *   `--terminal-app <name>` (Overrides `TERMINATOR_APP`)
            *   `--log-level <debug|info|warn|error|none>` (Overrides `TERMINATOR_LOG_LEVEL`)
            *   `--log-dir <path>` (Overrides `TERMINATOR_LOG_DIR`)
            *   `--grouping <off|project|smart>` (Overrides `TERMINATOR_WINDOW_GROUPING`)
            *   `--json`: (Used by `list` and `info` subcommands) Output results in JSON format to `stdout`.
            *   `-v, --verbose`: (Alias for `--log-level debug`)
            *   `-h, --help`: Display help information.
            *   `--version`: Display `terminator` CLI version.

    *   **3.2.4. Session Identification and Naming (Swift CLI Internal Rules):**
        *   A session is uniquely identified internally by a combination of a `projectHash` (SHA256 hash of the canonical `effectiveProjectPath`, or a fixed string like `"NO_PROJECT"` if no path) and the `resolvedTag`.
        *   **Tab Title Pattern:** Tabs managed by `terminator` will have their titles set to a strict, machine-readable format:
            `::TERMINATOR_SESSION::PROJECT_HASH=<SHA256_of_effectiveProjectPath_or_NO_PROJECT>::TAG=<resolvedTag_urlEncoded>::TTY_PATH=<ttyDevicePath_urlEncoded>::PID=<process_id_of_terminator_cli_that_created_it>::`
            *   The `resolvedTag` will be URL-encoded to handle special characters safely within the title.
            *   `TTY_PATH` and `PID` are for diagnostic purposes and potential future recovery, not primary identification.
            *   `terminator` expects to *own* these titles. If a tab's title matches this pattern but its content has been manually altered, `terminator` may still try to manage it, potentially overwriting user changes.
        *   **Display Name Synthesis:** For user-facing output (e.g., `list` command, AI messages), a human-friendly name is synthesized, e.g., `🤖💥 ProjectName / task_tag` or `🤖💥 _global_ / task_tag`. The `🤖💥` prefix is fixed.
        *   **Statelessness:** `terminator` CLI is stateless between its own invocations. Each action requiring interaction with an existing session re-identifies the target tab by scanning all terminal tabs for the specific `PROJECT_HASH` and `TAG` in their titles via AppleScript. It then re-fetches the current TTY device path for that tab.

    *   **3.2.5. Subcommands & Behavior (Swift CLI):**
        *   All subcommands accept global options like `--terminal-app`, `--log-level`, etc.
        *   Common parameters for session-targeting subcommands:
            *   `--project-path <path>`: Optional. Absolute path to the project. (This is the Swift CLI flag, remains kebab-case)
            *   `--tag <tag_string>`: Required (unless `--project-path` is used to derive it implicitly by Node.js wrapper and then passed explicitly). The actual tag string to use/find.
        *   **`execute [--project-path <path>] --tag <tag_string> [--command <string...>] [--execution-mode <background|foreground>] [--lines <N>] [--timeout-seconds <seconds>] [--focus-mode <force-focus|no-focus|default-behavior>]`**
            *   `--tag`: This is the resolved, sanitized tag passed by the Node wrapper.
            *   `--command <string...>`: The command and its arguments to execute. If empty, session is prepared, cleared, focused (if applicable).
            *   `--execution-mode`: Defaults to `foreground` unless `TERMINATOR_DEFAULT_BACKGROUND_EXECUTION` is true.
            *   `--lines`: Defaults to `TERMINATOR_DEFAULT_LINES`.
            *   `--timeout-seconds`: Overrides default timeouts.
            *   `--focus-mode`: Controls terminal focus. `default-behavior` respects `TERMINATOR_DEFAULT_FOCUS_ON_ACTION`. `force-focus` and `no-focus` override it.
            *   **Pre-execution Steps:**
                1.  Resolve target session (find existing or create new) based on `project_path` (for its hash, via `effectiveProjectPath`), `tag`, and `TERMINATOR_WINDOW_GROUPING`.
                2.  Determine TTY of the session tab. Check if session is "busy": uses `ps -t <tty> -o stat=,pgid=,comm=` to find any non-shell foreground process (e.g., status not 'S', 'Ss', 'Zs'; command not matching known shells like `bash`, `zsh`, `fish`).
                3.  If busy: Attempt to `stop` the foreground process group by sending `SIGINT` via `killpg()`. Wait for a fixed internal timeout (e.g., **3 seconds, non-configurable for V1**). If process still exists after timeout, `execute` fails with error code 4 ("Failed to stop busy process before execution.").
                4.  **Screen Clearing:** Always clear the terminal screen.
                    *   Apple Terminal: `do script "clear && clear"` in the tab (first `clear` for command history, second to attempt scrollback for some shells). Then, if possible, AppleScript `tell application "System Events" to keystroke "k" using command down` if the terminal app is frontmost. This is best-effort for scrollback.
                    *   iTerm2: `current_session clear_buffer` AppleScript command. This is highly effective.
                    *   Ghosty: Best effort, likely `do script "clear"`.
            *   **Execution:**
                *   Runs the command using AppleScript `do script "actual_command_to_run_here_with_logging_setup & disown"` in the target tab. The command is run such that its output goes to a temporary file associated with the session TTY (e.g., `/tmp/terminator_output_<tty_basename>_<timestamp>.log`). `terminator` then tails this file.
            *   **Waiting & Output:**
                *   **Foreground:** Tails output file. Waits for command completion (signaled by a unique EOF marker echoed after command, or process no longer running) or `timeout-seconds`. If timeout, sends `SIGTERM` then `SIGKILL` to the process group started by the command (identified via `ps` tracing from the shell process that ran the `do script`). Returns captured output.
                *   **Background:** Tails output file for `timeout-seconds` (for initial output). Returns captured initial output. Command continues running.
            *   Output capture includes both stdout and stderr, typically redirected in the `do script` command: `your_command > /tmp/output.log 2>&1`.
        *   **`read --project-path <path>] --tag <tag_string> [--lines <N>] [--focus-mode <force-focus|no-focus|default-behavior>]`**
            *   Finds session.
            *   Retrieves last `lines` from the current scrollback buffer via AppleScript (`contents of current_session` for iTerm2, `history` or `contents of selected tab` for Terminal, best-effort for Ghosty).
            *   Errors (code 3) if session not found.
        *   **`list [--project-path <path>] [--json]`**
            *   Scans all tabs of all windows of `TERMINATOR_APP` via AppleScript. Parses tab titles matching the `::TERMINATOR_SESSION::` pattern.
            *   For each matched tab, determines TTY and uses `ps` to check if `is_busy`.
            *   If `--json`, outputs a JSON array: `[{ "sessionIdentifier": "display_name", "project_path": "/abs/path/or_null", "tag": "actual_tag", "fullTabTitle": "...", "tty": "/dev/tty...", "isBusy": true/false, "windowIdentifier": "apple_script_id", "tabIdentifier": "apple_script_id" }, ...]`.
            *   If not `--json`, human-readable list.
        *   **`info [--json]`**
            *   Outputs `terminator` CLI version.
            *   Lists all resolved `TERMINATOR_*` configuration values.
            *   Includes output similar to `list` for all currently managed sessions.
            *   If `--json`, outputs a JSON object: `{ "version": "0.1.0", "configuration": { "app": "iTerm", "logLevel": "info", ... }, "sessions": [ ...list_output... ] }`.
        *   **`focus [--project-path <path>] --tag <tag_string>`**
            *   Finds session, brings its window and tab to the foreground using AppleScript.
        *   **`kill [--project-path <path>] --tag <tag_string> [--focus-mode <force-focus|no-focus|default-behavior>]`**
            *   Finds session and its TTY.
            *   Identifies the foreground process group (PGID) in that TTY (excluding common shells) using `ps -t <tty_basename> -o pgid=,sess=,stat=,command=`.
            *   If a non-shell foreground PGID is found:
                1.  `killpg(pgid, SIGINT)`. Wait `TERMINATOR_SIGINT_WAIT_SECONDS`. Check if process group still exists.
                2.  If still exists: `killpg(pgid, SIGTERM)`. Wait `TERMINATOR_TERM_WAIT_SECONDS`. Check again.
                3.  If still exists: `killpg(pgid, SIGKILL)`.
            *   **SIGINT Fallback:** If `killpg` with `SIGINT` fails due to permissions (EPERM), or if a clear non-shell PGID cannot be reliably determined but *some* activity is suspected, as a last resort, it will use AppleScript to bring the tab to focus and simulate `Ctrl+C` (`keystroke "c" using control down`). This is a focus-stealing fallback.
            *   If no specific process found, or after termination sequence, clears the terminal screen/scrollback of the session (same method as `execute` pre-execution). Tab is not closed.

    *   **3.2.6. Terminal Application Interaction:**
        *   **AppleScript:** Primary method for UI manipulations (finding/creating windows/tabs, setting titles, getting TTY, executing commands via `do script`, focusing, clearing screen/buffer).
            *   Scripts will be constructed dynamically. Care must be taken to properly escape content for AppleScript strings.
            *   Idempotency: Scripts designed to be idempotent where possible (e.g., "ensure tab with this title pattern exists and return its properties").
            *   Error Handling: Specific AppleScript error codes (e.g., -1743 permissions, -1728 object not found, -1708 app not running) will be caught and mapped to `terminator` exit codes (mostly exit code 3) with descriptive `stderr` messages. No automatic retries on AppleScript errors for V1.
        *   **Direct System Calls / `Process` Class (Swift):**
            *   `ps`: Used extensively for process discovery, status checking, PGID determination. Invoked with specific formatting options (`-o ...=`) to get machine-readable output.
            *   `killpg`: Used for sending signals directly to process groups.
        *   **Supported Terminals & Capability Check:**
            *   **Apple Terminal.app:** Full support target.
            *   **iTerm2:** Full support target. Preferred due to better AppleScript API (e.g., `clear_buffer`).
            *   **Ghosty:** Best-effort. At CLI startup, if `TERMINATOR_APP` is Ghosty, a simple `tell application "Ghosty" to get version` AppleScript is run. If it fails (e.g., -1708, -1743), `terminator` CLI exits with error code 2, indicating configuration issue. Min viable for Ghosty means `execute` (even if always new window), `read` (scrollback might be limited), and `kill` (might rely more on focus-stealing SIGINT). Screen clearing might be basic.

    *   **3.2.7. Logging (Swift CLI):**
        *   Simple file-based logger writing to `terminator-cli.log` inside `TERMINATOR_LOG_DIR`.
        *   Format: `[YYYY-MM-DDTHH:mm:ss.SSSZ LEVEL FILE:LINE FUNCTION] Message`. Example: `[2025-05-23T10:30:00.123Z DEBUG TerminatorCore.swift:42 executeCommand] Executing command 'ls -la' for tag 'my_build'`.
        *   Log rotation is **not** implemented in V1. Users should manage log file sizes manually if needed.
        *   **Privacy Note:** Debug level logs will contain full command strings, paths, and potentially sensitive output snippets. This will be documented in the README.
    *   **3.2.8. Error Handling (Swift CLI Exit Codes):**
        *   `0`: Success.
        *   `1`: General/Unknown Error (A catch-all for unexpected issues). `stderr` should contain details.
        *   `2`: Configuration Error (e.g., invalid `TERMINATOR_APP` name, app not found/scriptable, `TERMINATOR_LOG_DIR` unwritable and fallback also fails, invalid enum value for a config).
        *   `3`: AppleScript Communication/Execution Error (e.g., permissions error like -1743, application not running, specified object like a tab not found when expected).
        *   `4`: Process Control Error (e.g., `execute` failed to stop a busy process, `kill` attempted but process verification shows it's still running after all signals, command within `execute` fails to start).
        *   `5`: Invalid CLI Arguments/Subcommand Usage (Handled by `swift-argument-parser` typically, but custom validation can also use this).
        *   `6`: Session Not Found Error (A specific session (project/tag) was required but not found).
        *   `7`: Timeout Error (A command explicitly timed out during `execute` foreground, or Swift CLI internal safety timeout hit).

**4. Build and Packaging**

    *   **4.1. Swift CLI (`terminator`):**
        *   Compiled as a universal macOS binary using `swift build -c release --arch arm64 --arch x86_64 --product terminator`.
        *   Static linking of Swift standard libraries (`-Xswiftc -static-stdlib`) will be considered if it simplifies distribution, though typically not needed/recommended for system CLI tools.
        *   **Signing & Notarization:**
            *   Goal: AdHoc sign the binary (`codesign -s - path/to/terminator`).
            *   Notarization is a "nice-to-have" for V1 but might be deferred due to complexity. If not notarized, the README must clearly explain how users can manually allow Gatekeeper to run the binary (right-click open, or `xattr -d com.apple.quarantine swift-bin/terminator`).

    *   **4.2. NPM Package (`@steipete/terminator-mcp`):**
        *   `package.json`:
            *   `"os": ["darwin"]` to restrict installation to macOS.
            *   `"cpu": ["x64", "arm64"]` to indicate universal binary support.
            *   `"bin": { "terminator-mcp-server": "./dist/cli.js" }` (or similar, for the MCP server entry point if run standalone).
            *   `"files": ["dist/", "swift-bin/terminator", "README.md", "LICENSE"]`
        *   Scripts in `package.json`:
            *   `"build:swift"`: `swift build -c release --arch arm64 --arch x86_64 --product terminator && mkdir -p swift-bin && cp .build/apple/Products/Release/terminator swift-bin/terminator`
            *   `"build:ts"`: `tsc -p .` (assuming `tsconfig.json` is set up).
            *   `"build"`: `npm run build:swift && npm run build:ts`
            *   `"clean"`: `rm -rf dist/ swift-bin/ .build/`
            *   `"prepublishOnly"`: `npm run clean && npm run build`
            *   `"postinstall"`: `chmod +x swift-bin/terminator` (Ensures the bundled binary is executable). This script is critical.
        *   Bundles the `terminator` Swift binary in `swift-bin/`, compiled TypeScript (Node.js wrapper) in `dist/`.

**5. User Documentation (`README.md` for `@steipete/terminator-mcp`)**

    *   **Overview:** Purpose, key features.
    *   **Installation:** `npx @steipete/terminator-mcp some-command` (if applicable for direct npx use beyond MCP) or how to integrate as an MCP plugin.
    *   **Permissions Setup (Critical):**
        *   Detailed, step-by-step instructions with screenshots/GIF suggestions for granting macOS Automation permissions:
            *   To the primary terminal application (`Terminal.app`, `iTerm.app`) to control "System Events" and itself.
            *   To the AI Agent / MCP Host (e.g., Cursor, VS Code) to control the primary terminal application.
            *   Explanation of *why* these are needed (AppleScript).
        *   How to manually run the `swift-bin/terminator` once if Gatekeeper blocks it due to not being notarized.
    *   **Configuration:**
        *   Comprehensive table of all `TERMINATOR_*` environment variables: Name, Description, Allowed Values, Default Value.
        *   Examples of how to set them (e.g., in `.zshrc`, `.bash_profile`, or IDE-specific settings).
    *   **AI Tool Usage (`terminator.execute`):**
        *   Explanation of the `action` parameter (and its default to `execute`).
        *   Table listing each `action` value (`execute`, `read`, `list`, `info`, `focus`, `kill`).
        *   For each action, list applicable `options` (`project_path`, `tag`, `command`, `background`, `lines`, `timeout`, `focus`).
        *   Clear examples of AI invoking the tool for common scenarios.
    *   **Troubleshooting:**
        *   Common errors:
            *   Permissions issues (Error -1743): Link back to permissions setup.
            *   "Swift CLI binary not found": Suggest reinstall.
            *   `TERMINATOR_APP` misconfiguration.
        *   Log file locations: `TERMINATOR_LOG_DIR` for Swift CLI logs, and how Node wrapper might log (e.g., to MCP host's logs).
        *   How to check Swift CLI version: `swift-bin/terminator --version`.
    *   **Privacy and Security Considerations:**
        *   Explicitly state that commands are executed with user-level privileges.
        *   Warn that debug logs (`TERMINATOR_LOG_LEVEL=debug`) for the Swift CLI will contain the full text of commands executed, their arguments, and potentially sensitive path information. Advise caution when sharing debug logs.
    *   **Supported Terminal Applications:** List (Terminal, iTerm2, Ghosty with caveats).

**6. Future Enhancements (Post V1)**

    *   **`terminator doctor` Swift CLI command:** A self-check utility to diagnose common issues (permissions, app scriptability, configuration).
    *   **Non-focus-stealing visual feedback for long background tasks:** E.g., optional, user-configurable system notifications on command completion/error for background tasks, or a subtle menu bar indicator.
    *   **YAML configuration file support:** As an alternative/override to environment variables if they become too numerous or complex for users.
    *   **Log rotation for Swift CLI logs:** Implement size-based or time-based log rotation.
    *   **More sophisticated "smart" grouping heuristics:** Potentially based on active IDE project, git repository root, or user-defined rules.
    *   **Option for `kill` action to also close the tab/window.**
    *   **Direct TTY interaction (pty):** Explore using pseudo-terminals directly from Swift for more robust output capture and control, reducing AppleScript reliance for command execution itself (AppleScript would still be needed for window/tab management). This is a major architectural change.
    *   **More granular session state persistence:** Small state file to remember last active TTY for a session to speed up re-acquisition, if statelessness proves too slow for many tabs.