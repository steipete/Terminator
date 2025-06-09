# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terminator is a Model Context Protocol (MCP) plugin that provides AI agents with robust control over macOS terminal sessions. It consists of two main components:

1. **Node.js MCP Wrapper** (`@steipete/terminator-mcp`) - NPM package implementing MCP server logic
2. **Swift CLI** (`terminator`) - Native macOS executable for terminal interactions

The project isolates long-running or potentially hanging commands to protect AI workflows while minimizing user focus disruption.

## Common Development Commands

### Building
```bash
# Build everything (TypeScript + Swift)
npm run build

# Build TypeScript only
npm run build:ts

# Build Swift CLI only (creates universal binary)
npm run build:swift

# Clean build artifacts
npm run clean
```

### Testing
```bash
# Run E2E tests
npm test

# Run E2E tests in watch mode
npm run test:watch

# Run Swift tests
npm run test:swift

# Run AppleScript tests
npm run test:applescript

# Verify AppleScript consistency
npm run verify:applescript

# Run tests with coverage
npm run test:coverage
```

### Development
```bash
# Start development server with auto-rebuild
npm run dev

# Format Swift code
npm run format:swift

# Lint Swift code
npm run lint:swift

# Launch MCP inspector for debugging
npm run inspector
```

### Release Preparation
```bash
# Prepare release (updates version, creates changelog)
npm run prepare-release

# Note: Publishing is done via npm publish after running prepublishOnly
```

## High-Level Architecture

### Component Communication Flow
```
AI Agent (Claude) <--MCP Protocol--> Node.js Wrapper <--Process Spawn--> Swift CLI <--AppleScript/System APIs--> Terminal Apps
```

### Key Design Principles

1. **Stateless Operation**: The Swift CLI maintains no state between invocations. Each command re-identifies sessions by scanning terminal tabs for specific title patterns.

2. **Session Identification**: Sessions are uniquely identified by:
   - Project hash (SHA256 of project path)
   - Tag (user-defined or derived from project path)
   - Tab titles follow pattern: `::TERMINATOR_SESSION::PROJECT_HASH=<hash>::TAG=<tag>::TTY_PATH=<tty>::PID=<pid>::`

3. **Terminal Support**: Full support for Apple Terminal and iTerm2, best-effort for Ghosty. The Swift CLI uses AppleScript for UI manipulation and system calls for process management.

4. **Error Handling**: Swift CLI uses specific exit codes:
   - 0: Success
   - 1: General error
   - 2: Configuration error
   - 3: AppleScript error
   - 4: Process control error
   - 5: Invalid arguments
   - 6: Session not found
   - 7: Timeout error

### Node.js Wrapper Responsibilities

- Registers single MCP tool `terminator.execute` with dynamic description based on environment
- Validates and coerces AI input parameters
- Manages Swift CLI process lifecycle with timeouts
- Formats output for AI consumption
- Handles MCP cancellation requests

### Swift CLI Architecture

The Swift CLI follows a command pattern with these subcommands:
- `exec` (execute) - Run commands in terminal sessions
- `read` - Read session output/scrollback
- `list` - List active sessions
- `info` - Show version and configuration
- `focus` - Bring session to foreground
- `kill` - Terminate session processes

Each command is implemented in `cli/Sources/TerminatorCLI/Commands/` with shared logic in:
- `TerminalControlling.swift` - Protocol defining terminal operations
- `Implementations/` - Terminal-specific implementations (AppleTerminal, iTerm, Ghosty)
- `Models/` - Data structures and configuration
- `Utilities/` - Logging, process management, string helpers

### Environment Variables

The system respects these `TERMINATOR_*` environment variables (see docs/spec.md for full details):
- `TERMINATOR_APP` - Terminal application (Terminal/iTerm/Ghosty)
- `TERMINATOR_LOG_LEVEL` - Logging verbosity
- `TERMINATOR_LOG_DIR` - Log file location
- `TERMINATOR_WINDOW_GROUPING` - Tab grouping strategy (off/project/smart)
- `TERMINATOR_DEFAULT_LINES` - Default output lines to capture
- `TERMINATOR_BACKGROUND_STARTUP_SECONDS` - Background command startup timeout
- `TERMINATOR_FOREGROUND_COMPLETION_SECONDS` - Foreground command completion timeout
- `TERMINATOR_DEFAULT_FOCUS_ON_ACTION` - Whether to focus terminal on actions

## Testing Strategy

1. **E2E Tests** (`tests/e2e/`, `src/__tests__/*.e2e.test.ts`) - Test full MCP tool invocation flow
2. **Swift Unit Tests** (`cli/Tests/TerminatorCLITests/`) - Test Swift CLI components
3. **AppleScript Tests** (`cli/Tests/AppleScriptTests/`) - Verify AppleScript interactions

When adding features:
- Add E2E tests for the full flow
- Add Swift unit tests for new Swift functionality
- If modifying AppleScript, update consistency tests

## Key Files and Their Purpose

- `src/index.ts` - MCP server entry point
- `src/tool.ts` - MCP tool definition and handler
- `src/swift-cli.ts` - Swift CLI invocation logic
- `src/config.ts` - Configuration management
- `src/utils.ts` - Utility functions
- `cli/Sources/TerminatorCLI/main.swift` - Swift CLI entry point
- `docs/spec.md` - Detailed technical specification

## Important Notes

- Always run lint/typecheck before committing Swift changes
- The Swift CLI binary must be executable (`chmod +x bin/terminator`)
- AppleScript permissions are required - first run will prompt user
- Debug logs may contain sensitive information (commands, paths)
- The project targets macOS 14.0+ and requires Node.js 18.0+

## Development Philosophy

### No Backward Compatibility
This project does NOT maintain backward compatibility. We prioritize:
- Clean, modern code over legacy support
- Rapid iteration and improvement
- Breaking changes are acceptable and expected
- Users should always use the latest version
- Old versions are not supported

When making changes:
- Feel free to break existing APIs if it improves the design
- Remove deprecated code immediately
- Don't add compatibility layers or migration paths
- Focus on the best solution for current needs