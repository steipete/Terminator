# Changelog

All notable changes to Terminator will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.6.0] - 2025-05-22

### Added
- **🚀 Enhanced Architecture**: Completely refactored main function into modular components (`executeCommandInTerminal`, `parseArgumentsEnhanced`, `captureTerminalOutputWithRetry`)
- **🛡️ Advanced Process Management**: Multi-strategy process interruption system with SIGINT → SIGTERM → SIGKILL progression and configurable delays
- **🔍 Smart Output Capture**: Retry logic with 3 attempts, multiple capture methods (`history` with `contents` fallback), and comprehensive diagnostics
- **✅ Enhanced Path Validation**: Regex-based flag detection for command patterns (`--`, `-[a-zA-Z]`), path existence checking, and 500-character limits
- **⚡ Performance Optimizations**: Shell-based string trimming for large texts, adaptive polling (frequent → reduced frequency), optimized Terminal interactions
- **📊 Comprehensive Status Reporting**: Detailed process interruption status, capture attempt logging, warning system for edge cases
- **🔧 Enhanced Configuration System**: Centralized timing parameters, configurable retry mechanisms, adaptive delay multipliers

### Changed
- **Script Version**: Updated to v0.6.0 "T-1000" with significantly improved reliability and performance
- **Argument Processing**: Complete rewrite with robust record handling and direct property assignment to prevent AppleScript variable conflicts
- **Error Handling**: Enhanced error messages with specific resolution guidance and actionable suggestions
- **String Processing**: Optimized `trimWhitespace` function with shell command fallback for large strings (>1000 characters)
- **Process Detection**: Enhanced busy process identification with PID tracking and comprehensive shell detection

### Enhanced
- **Robustness**: Multiple fallback strategies for Terminal interaction failures, comprehensive edge case handling
- **User Experience**: Detailed progress indication, enhanced status messages, improved error context
- **Maintainability**: Modular function architecture, comprehensive documentation, clean separation of concerns
- **Backward Compatibility**: 100% API compatibility with v0.5.1 while providing enhanced functionality

### Technical Improvements
- **Adaptive Polling**: Dynamic polling intervals that start frequent and reduce over time for optimal responsiveness
- **Enhanced Record Handling**: Fixed AppleScript record manipulation issues that caused variable conflicts
- **Multi-Method Capture**: Primary `history` property with `contents` property fallback for maximum reliability
- **Process Interruption Matrix**: Configurable signal progression with success tracking and fallback to keyboard interrupts
- **Comprehensive Validation**: Path format validation, task tag format checking, argument count verification

### Performance Gains
- **Reduced Terminal Interactions**: Batched operations and optimized AppleScript bridge usage
- **Optimized String Operations**: Shell-based processing for large content with character-by-character fallback
- **Smart Caching**: Reduced redundant Terminal state queries and process lookups
- **Efficient Error Propagation**: Streamlined error handling with minimal overhead

### Notes
- Maintains full backward compatibility with existing v0.5.1 usage patterns
- Output capture reliability remains a known limitation inherited from Terminal.app/AppleScript timing
- All core functionality (session management, project grouping, automatic cd, process management) works reliably
- Enhanced version provides significant improvements in robustness, performance, and user experience

## [v0.5.1] - 2025-01-22

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

## [v0.4.7] - 2025-01-22

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

## [v0.4.4] - Initial Release

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