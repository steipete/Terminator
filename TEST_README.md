# Terminator Test Suite

This directory contains a comprehensive test suite for the Terminator script.

## Running Tests

To run the complete test suite:

```bash
osascript test_terminator.scpt
```

## Test Coverage

The test suite validates:

1. **Basic Command Execution** - Simple command execution and output capture
2. **Session Creation** - Creating new terminal sessions with unique tags
3. **Project Path Support** - Using project paths for session organization
4. **Multiple Commands** - Running multiple commands in the same session
5. **Empty Session Creation** - Creating sessions without initial commands
6. **Usage Display** - Proper help text when called without arguments
7. **Invalid Tag Handling** - Error handling for invalid tag names
8. **Directory Persistence** - Directory changes persisting across commands

## Test Environment

- Creates temporary test project at `/tmp/terminator_test_project`
- Uses test session tags prefixed with `test_` to avoid conflicts
- Automatically cleans up test sessions and temporary files
- Safe to run multiple times

## Expected Output

```
🚀 Starting Terminator Test Suite
==================================
🔧 Setting up test environment...
🧪 Test 1: Basic Command Execution
✅ PASSED: Basic Command Execution
🧪 Test 2: Session Creation
✅ PASSED: Session Creation
...
🧹 Cleaning up test environment...
==================================
🏁 Test Suite Complete
✅ Passed: 8
❌ Failed: 0
📊 Total: 8
🎉 All tests passed!
SUCCESS: All 8 tests passed.
```

## Prerequisites

- macOS with Terminal.app
- AppleScript automation permissions for Terminal.app and System Events.app
- The main `terminator.scpt` file in the same directory