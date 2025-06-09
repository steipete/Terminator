# Changelog

All notable changes to Terminator will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0-beta.1] - 2025-01-06

### Changed
- **MCP Best Practices Compliance**: Full alignment with MCP best practices
  - Removed all console output to prevent MCP client disruption
  - Added temp directory fallback for logger when default paths are not writable
  - Enhanced prepare-release script with E2E tests and Swift analyzer
  - Improved error reporting without stdio output

### Added
- **Enhanced Release Process**: prepare-release.js now includes:
  - E2E test execution
  - Swift analyzer checks
  - Build cache cleanup
  - More comprehensive validation

### Fixed
- **Logger Configuration**: Fixed potential stdio output during logger initialization
- **MCP Compliance**: Ensured zero console output during all operations

## [1.0.0-alpha.12] - 2025-05-26

### Changed
- **iTerm Implementation**: Major refactoring to improve process management
  - Simplified process ID handling to work directly with session IDs
  - Removed unnecessary ProcessUtilities code and getProcessInfo functionality
  - Updated AppleScript integration for more reliable command execution
  - Improved error handling and reduced AppleScript usage

### Fixed
- **Process Management**: Fixed issues with iTerm process tracking and session management
- **Code Cleanup**: Removed 130+ lines of unused code, improving maintainability

### Added
- **Enhanced Testing**: Added comprehensive test coverage and improved test infrastructure
- **Better Error Messages**: More descriptive error handling throughout iTerm implementation

## [1.0.0-alpha.11] - 2025-05-26

### Fixed
- **Empty Command Handling**: Fixed issue where empty command strings were incorrectly passed as `--command ""` to Swift CLI
  - Empty commands now properly omit the `--command` flag entirely
  - This allows "prepare session" functionality to work correctly (clear terminal, focus window)
  - Both empty string (`""`) and undefined commands are handled correctly

### Added
- **Test Coverage Planning**: Created comprehensive E2E and unit test templates for future testing
  - Covers edge cases like empty commands, special characters, invalid parameters
  - Tests for all actions (exec, read, list, info, focus, kill)
  - Parameter validation and CLI argument generation tests

## [1.0.0-alpha.10] - 2025-05-26

### Fixed
- **Execa Compatibility**: Fixed `signal` option renamed to `cancelSignal` in newer execa versions
- **Debug Logging**: Added version number to all debug log entries (e.g., `[TerminatorMCP v1.0.0-alpha.10 NodeJS DEBUG]`)

### Changed
- **Version Management**: Centralized version reading in config module to avoid duplication
- **Error Messages**: Swift CLI errors are now properly captured and passed to the client

## [1.0.0-alpha.9] - 2025-05-26

### Added
- **Enhanced Error Logging**: Added detailed error logging for Swift CLI execution failures
  - Logs error code, exit code, signal, stdout/stderr snippets, and execution details
  - Helps diagnose issues when Swift CLI crashes or fails to execute

### Known Issues
- Swift CLI crashing with Range bounds error on command execution (investigating)

## [1.0.0-alpha.8] - 2025-05-26

### Changed
- **Refactored Swift CLI invocation**: Replaced manual spawn handling with `execa` library
  - Cleaner, more maintainable code with better error handling
  - Automatic error code mapping using `errno` for friendly error messages
  - Simplified timeout and cancellation logic with AbortController
  - Better TypeScript types and error handling

### Added
- **Dependencies**: Added `execa` and `errno` for improved process management
- **Type definitions**: Added custom TypeScript definitions for errno module

## [1.0.0-alpha.7] - 2025-05-26

### Added
- **CLI Parameter Error Handling**: Added proper handling for exit code 64 (command line usage errors)
  - Invalid parameters now show clear error messages with usage information
  - Extracts and displays correct usage syntax when available

### Fixed
- **Info Command**: Fixed issue where `--project-path` was incorrectly passed to info command
- **Error Message Clarity**: CLI parameter errors are now properly captured and displayed to users

## [1.0.0-alpha.6] - 2025-05-26

### Added
- **Enhanced Error Diagnostics**: Comprehensive error messages when Swift CLI terminates unexpectedly
  - Specific handling for spawn errors (ENOENT, EACCES, EPERM)
  - Detection of common issues like missing permissions or binary corruption
  - Detailed diagnostic information including terminal app, action, command, and project path
  - Clear troubleshooting steps for each error type
  - Helpful guidance for automation permission issues

### Changed
- **Error Handling**: Improved error handling in both tool.ts and swift-cli.ts for better user experience
  - Process spawn errors now provide specific, actionable error messages
  - Null exit codes are handled with detailed diagnostics instead of generic errors

### Known Issues
- Swift tests failing with Range bounds error on macOS 14.0 (investigating)

## [1.0.0-alpha.5] - 2025-01-26

### Fixed
- **Dynamic Version Display**: Tool description now shows the correct version from package.json (including alpha/beta versions)
- **Version Import**: Fixed version reading to dynamically load from package.json instead of hardcoded value

## [1.0.0-alpha.4] - 2025-01-26

### Fixed
- **Error Handling**: Improved handling of null exit codes from Swift CLI (typically permission issues)
- **Error Messages**: Added helpful guidance for automation permission issues
- **Documentation**: Enhanced troubleshooting section with common "Swift CLI Code null" error solutions
- **README**: Fixed broken logo image URL (capital T in repository name)

## [1.0.0-alpha.3] - 2025-01-26

### Fixed
- **AppleScript Error Handling**: Fixed "Can't get index of every tab of window id" error when Terminal windows are closed
- **Session Listing**: Made session listing more robust by handling inaccessible windows/tabs gracefully

## [1.0.0-alpha.2] - 2025-01-26

### Fixed
- **MCP Server Startup**: Added missing `terminator-mcp` binary entry point in package.json
- **Executable Permission**: Added shebang to index.ts for proper executable generation

## [1.0.0-alpha.1] - 2025-01-26

### Added
- **Comprehensive Release Process**: Complete npm release preparation script from Peekaboo project
- **AppleScript Test Integration**: AppleScript tests are now part of the release process
- **AppleScript Consistency Verification**: New script to ensure AppleScript code consistency between test files and source code
- **Universal Binary Support**: Enhanced build process for creating optimized universal binaries

### Changed
- **Major Version Bump**: Moving to 1.0.0-alpha.1 to indicate significant maturity and stability
- **Test Infrastructure**: Improved AppleScript test runner with better output handling and pattern matching

### Fixed
- **Swift Tests**: Fixed all 47 failing Swift tests
  - Fixed Swift 5.9 if-let expression syntax compatibility issues
  - Fixed AnyCodable value access by adding property getters
  - Fixed InfoCommand JSON test structure issues
  - Fixed AppleScriptBridge nested list handling (root cause of iTerm test failures)
- **AppleScript Tests**: Fixed failing createWindow test and improved test resilience

## [0.5.2] - 2025-01-25

### Added
- **Release Preparation**: Added comprehensive release preparation script with Git, TypeScript, Swift, and package verification checks
- **Universal Binary Build**: Added build script to create optimized universal binaries (arm64 + x86_64) with size reduction
- **SwiftFormat Configuration**: Added .swiftformat configuration for consistent code style
- **Swift Version File**: Added .swift-version file specifying Swift 5.9
- **Package Metadata**: Added repository, keywords, bugs, homepage, and engine requirements to package.json

### Changed
- **Code Quality**: Eliminated all 56 SwiftLint violations through comprehensive refactoring:
  - Split monolithic test file (1438 lines) into 9 focused test files
  - Extracted helper methods to fix function_body_length violations
  - Split large files to fix file_length violations
  - Introduced parameter structs to fix function_parameter_count violations
  - Created result structs to fix large_tuple violations
- **Test Organization**: Restructured test suite with BaseTerminatorTests class for shared utilities
- **Swift Code Structure**: Refactored large Swift files into smaller, focused modules for better maintainability
- **Build Process**: Replaced platform-specific build script with universal binary builder
- **MCP Tool Parameters**: Renamed AI-facing `projectPath` parameter to `project_path` (snake_case) for the `terminator.execute` tool.
- **MCP Tool Parameters**: Flattened `options` parameter for `terminator.execute` tool, moving sub-fields (`tag`, `command`, `background`, `lines`, `timeout`, `focus`) to the root level of tool parameters.
- **MCP Tool Parameters**: Made `project_path` a mandatory parameter for `terminator.execute`.
- **MCP Tool Parameters**: `tag` parameter is now optional for `terminator.execute`, with its default derived from `project_path` if not provided.
- **MCP Tool Parameters**: Expanded description for the `command` parameter in `terminator.execute`.
- **MCP Tool Description**: Dynamically appends Terminator MCP version and configured terminal app (e.g., "Terminator MCP 0.1.0 using iTerm") to the main description of the `terminator.execute` tool.
- **MCP Tool Description**: `action` parameter description now lists all possible enum values and specifies its default (`exec`).
- **Documentation**: Updated `README.md` to reflect all MCP tool parameter and description changes.
- **Internal**: Updated TypeScript MCP server source (`src/types.ts`, `src/tool.ts`, `src/index.ts`, `src/config.ts`) and documentation (`docs/spec.md`) to reflect these parameter changes.

### Fixed
- Ensured `docs/spec.md` is consistent with the updated MCP tool parameters and descriptions.

## [0.5.1] - 2025-01-22

### Added
- **Enhanced Project Path Detection**: Reliable detection of project paths as the first argument when they start with "/" and don't contain command flags
- **Automatic Directory Change**: When a project path is provided, the script automatically prepends `cd <path> &&` to commands
- **Improved Text Processing**: Enhanced logic to better distinguish meaningful terminal output from shell prompts and script messages
- **Comprehensive Test Coverage**: Updated test suite with 10 tests including specific validation for v0.5.1 features

### Changed
- **Argument Parsing Logic**: Complete rewrite of v0.5.0 argument parsing with more robust project path detection using `isValidPath()` heuristics
- **Enhanced Error Messages**: More descriptive error messages with better context about project paths and session creation
- **Script Version**: Updated to v0.5.1 "T-800" with improved reliability
- **Test Suite**: Updated to properly validate output capture and avoid false positives from error messages

### Fixed
- **Multi-line Text Processing**: Fixed misuse of `lineIsEffectivelyEmptyAS()` function on multi-line terminal buffers
- **Project Path Integration**: Improved integration between project path detection and command execution
- **Session Title Generation**: Enhanced title generation with proper project name extraction

### Technical Notes
- Maintains full backward compatibility with existing usage patterns
- Output capture reliability remains a known limitation inherited from previous versions
- All core functionality (session management, project grouping, automatic cd) works reliably
- 9/10 tests pass with comprehensive validation of major features

## [0.4.7] - 2025-01-22

### Added
- **Project Path Support**: Added optional project path as first argument for better organization
- **Fuzzy Target Grouping**: New sessions can automatically group into existing project windows
- **Enhanced Title Generation**: Titles now include both project and task identifiers
- **Path Validation**: Added `isValidPath()` function to validate project paths
- **Path Component Extraction**: Added `getPathComponent()` function for extracting project names
- **Logo Support**: Added placeholder for project logo in README

### Changed
- **Argument Parsing**: Completely redesigned to support project paths as optional first argument
- **Session Management**: Enhanced `ensureTabAndWindow()` to support project grouping and fuzzy matching
- **Tab Creation**: Now supports creating tabs in existing project windows vs. always new windows
- **Error Messages**: More descriptive error messages with context about project paths and task tags
- **Usage Documentation**: Complete rewrite with project-focused examples and combat-themed presentation
- **README**: Transformed from basic description to comprehensive Terminator-themed documentation

### Enhanced
- **Process Termination**: Improved process interruption with better handling for existing vs. new tabs
- **Session State Tracking**: Enhanced tracking of newly created vs. existing sessions
- **Configuration**: Added new properties for project and task identifiers in titles
- **MCP Integration**: Added promotion for compatible MCP servers (macOS Automator MCP and Claude Code MCP)

### Fixed
- **tabTitlePrefix Reference**: Fixed ReferenceError in usage text generation
- **Session Creation Logic**: Improved logic for when to allow session creation
- **Tab Title Setting**: Better handling of custom titles for new tabs

### Technical Improvements
- **Code Organization**: Better separation of concerns with dedicated helper functions
- **Error Handling**: More robust error handling throughout the script
- **Documentation**: Comprehensive inline documentation and usage examples
- **Version Tracking**: Updated from v0.4.4 to v0.4.7 with proper version metadata

## [0.4.4] - Initial Release

### Added
- **Basic Terminal Session Management**: Create and manage tagged terminal sessions
- **Command Execution**: Execute shell commands in dedicated terminal tabs
- **Process Interruption**: Ability to interrupt busy processes before new commands
- **Output Capture**: Retrieve specified number of lines from terminal history
- **Session Persistence**: Reuse existing sessions by tag name
- **Basic Tab Management**: Create new tabs with custom titles
- **Configuration Properties**: Configurable timeouts, delays, and line counts
- **Usage Documentation**: Basic usage instructions and examples

### Features
- Simple tag-based session identification
- Command execution with timeout protection
- History reading with configurable line counts
- Process termination using TTY kill and Ctrl-C
- Screen clearing before new commands
- Basic error handling and reporting
- AppleScript automation permissions support