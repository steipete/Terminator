# Hybrid Mode Guide

## Overview

Terminator's Hybrid Mode combines the power of macOS Accessibility APIs (via AXorcist) with traditional AppleScript automation to deliver significantly improved performance while maintaining full functionality. This mode is currently experimental and can be enabled via environment variables.

## What is Hybrid Mode?

In traditional mode, Terminator uses AppleScript exclusively for all terminal interactions. While reliable, this approach can be slow, especially for operations like:

- Enumerating windows and tabs
- Focusing specific sessions
- Checking session state

Hybrid Mode leverages the AXorcist library to use native Accessibility APIs for UI operations while retaining AppleScript for terminal-specific features that have no accessibility equivalents.

## Performance Improvements

Expected performance gains in Hybrid Mode:

| Operation        | Traditional | Hybrid | Improvement |
| ---------------- | ----------- | ------ | ----------- |
| List Windows     | ~200ms      | ~20ms  | 10x faster  |
| Focus Session    | ~150ms      | ~15ms  | 10x faster  |
| Check Busy State | ~100ms      | ~10ms  | 10x faster  |
| Activate App     | ~300ms      | ~30ms  | 10x faster  |

## Enabling Hybrid Mode

### Quick Start

Enable all hybrid features at once:

```bash
export TERMINATOR_EXPERIMENTAL_AX=true
```

### Granular Control

Enable specific features individually:

```bash
# Use AX for window/tab enumeration
export TERMINATOR_AX_WINDOWS=true

# Use AX for focus operations
export TERMINATOR_AX_FOCUS=true

# Use AX for busy state checking (Terminal.app only)
export TERMINATOR_AX_BUSY=true

# Control session data enrichment
export TERMINATOR_ENRICH_SESSIONS=true  # Default: true
```

## Permissions Required

Hybrid Mode requires additional permissions beyond the standard Apple Events permission:

1. **Apple Events** (always required)
   - Allows AppleScript control of terminal applications
   - Required for command execution and output reading

2. **Accessibility** (required for Hybrid Mode)
   - Allows direct UI element inspection and manipulation
   - Required for fast window/tab enumeration and focus operations

When you first enable Hybrid Mode, macOS will prompt you to grant Accessibility permission to the Terminator CLI. You must grant this permission in System Settings > Privacy & Security > Accessibility.

## How It Works

### Operations Using Accessibility APIs

These operations are significantly faster in Hybrid Mode:

- **Window Enumeration**: Directly queries UI hierarchy
- **Tab Discovery**: Finds tabs without AppleScript iteration
- **Focus Management**: Sets focus without scripting delays
- **Application Activation**: Uses system APIs instead of AppleScript

### Operations Still Using AppleScript

These operations have no accessibility equivalents:

- **Command Execution**: `do script` command
- **Output Reading**: Terminal scrollback access
- **TTY Information**: Device path retrieval
- **Session Creation**: New window/tab creation
- **Custom Title Setting**: Modifying tab titles

### Automatic Fallback

If an accessibility operation fails (e.g., due to permissions or API limitations), Terminator automatically falls back to the traditional AppleScript approach. This ensures reliability even in edge cases.

## Terminal-Specific Features

### Apple Terminal

- Full AX support for window/tab enumeration
- Native `AXBusy` attribute for busy state checking
- Reliable tab title access via accessibility

### iTerm2

- Enhanced tab discovery (handles both tab group and toolbar modes)
- Session enrichment with iTerm-specific data
- Optimized focus operations

### Ghosty

- Limited accessibility support (best-effort)
- Falls back to AppleScript for most operations

## Troubleshooting

### Permission Issues

If Hybrid Mode isn't working:

1. Check if Accessibility permission is granted:

   ```bash
   # Run Terminator info command with debug logging
   TERMINATOR_LOG_LEVEL=debug terminator info
   ```

2. Re-grant permissions if needed:
   - System Settings > Privacy & Security > Accessibility
   - Remove and re-add Terminator

### Performance Not Improved

If you don't see performance improvements:

1. Verify Hybrid Mode is actually enabled:

   ```bash
   # Check logs for "Hybrid" mentions
   TERMINATOR_EXPERIMENTAL_AX=true TERMINATOR_LOG_LEVEL=debug terminator list
   ```

2. Look for fallback messages in logs indicating AX operations failed

### Debugging

Enable debug logging to see which mode is being used:

```bash
export TERMINATOR_LOG_LEVEL=debug
export TERMINATOR_EXPERIMENTAL_AX=true
```

Look for log messages like:

- "Using AX for session enumeration"
- "Using AX for session focus"
- "AX operation failed, falling back to AppleScript"

## Best Practices

1. **Start with Full Hybrid Mode**: Use `TERMINATOR_EXPERIMENTAL_AX=true` initially
2. **Monitor Logs**: Watch for any fallback behavior
3. **Report Issues**: If you encounter problems, disable specific features to isolate the issue
4. **Performance Testing**: Use the built-in benchmarks to verify improvements

## Future Enhancements

As AXorcist and macOS accessibility APIs evolve, we plan to:

- Migrate more operations from AppleScript to AX
- Improve Terminal.app integration
- Add support for more terminal emulators
- Reduce or eliminate AppleScript dependency entirely

## Migration Path

For users transitioning to Hybrid Mode:

1. **Phase 1**: Enable `TERMINATOR_EXPERIMENTAL_AX` and monitor for issues
2. **Phase 2**: If stable, this becomes your default configuration
3. **Phase 3**: In a future release, Hybrid Mode may become the default

## Technical Details

For developers and contributors:

### Architecture

- `HybridTerminalControlBase`: Base class implementing the hybrid logic
- `HybridAppleTerminalControl`: Terminal.app-specific optimizations
- `HybridITermControl`: iTerm2-specific optimizations
- `AXorcistProvider`: Wrapper around AXorcist library
- `AccessibilityProviding`: Protocol for testability

### Adding New Features

To add accessibility support for a new operation:

1. Add method to `AccessibilityProviding` protocol
2. Implement in `AXorcistProvider`
3. Update hybrid controller to use AX with fallback
4. Add tests for both success and fallback paths
5. Document any terminal-specific behavior

## Feedback

Hybrid Mode is experimental. Please report your experience:

- Performance improvements observed
- Any compatibility issues
- Feature requests for AX migration

File issues at: https://github.com/anthropics/terminator-mcp/issues
