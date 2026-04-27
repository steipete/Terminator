# AppleScript to Accessibility API Mapping Analysis

## Overview

This document analyzes the AppleScript operations in Terminator and evaluates which can be replaced with macOS Accessibility APIs. The analysis considers feasibility, performance, reliability, and limitations.

## Key Findings

### Operations That CAN Be Replaced with Accessibility APIs

| AppleScript Operation         | Accessibility API Equivalent                                                                                 | Notes                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------- |
| **Window Enumeration**        | `AXUIElementCopyAttributeValue` with `kAXWindowsAttribute`                                                   | Can enumerate all windows and their properties |
| **Tab/Session Enumeration**   | `AXUIElementCopyAttributeValue` with `kAXChildrenAttribute`                                                  | Terminal tabs are exposed as AX children       |
| **Focus Window/Tab**          | `AXUIElementSetAttributeValue` with `kAXFocusedAttribute` + `AXUIElementPerformAction` with `kAXRaiseAction` | Can focus specific UI elements                 |
| **Get Window/Tab Properties** | `AXUIElementCopyAttributeValue` with various attributes                                                      | Can read titles, positions, sizes, etc.        |
| **Send Keystrokes**           | `CGEventPost` or `AXUIElementPostKeyboardEvent`                                                              | Can send keyboard events including Ctrl+C      |
| **Activate Application**      | `NSWorkspace.shared.activateApplication` or `AXUIElementPerformAction` with `kAXRaiseAction`                 | Bring app to foreground                        |
| **Check Tab Busy State**      | `AXUIElementCopyAttributeValue` with custom attributes                                                       | Terminal.app exposes busy state via AX         |

### Operations That MUST Remain in AppleScript

| AppleScript Operation              | Reason Cannot Use AX                                 | Alternative                                    |
| ---------------------------------- | ---------------------------------------------------- | ---------------------------------------------- |
| **Execute Commands (`do script`)** | No AX API for shell command execution                | None - core terminal functionality             |
| **Read Terminal Output/History**   | AX only provides visible text, not scrollback buffer | None - AppleScript `history` property required |
| **Get TTY Device Path**            | Terminal-specific property not exposed via AX        | Could parse from process info                  |
| **Set Custom Title**               | Write access to terminal-specific properties         | None - AppleScript required                    |
| **Create New Window/Tab**          | AX can't create new UI elements                      | Could use menu bar automation                  |
| **Clear Terminal**                 | No direct AX action for clear                        | Could send Cmd+K via keystroke                 |
| **Navigate to Directory**          | Requires command execution                           | None - must use `do script`                    |

### Operations with Mixed Approaches

| Operation                  | Current Method                         | Hybrid Approach                                          |
| -------------------------- | -------------------------------------- | -------------------------------------------------------- |
| **Session Identification** | Parse custom titles via AppleScript    | Use AX to find windows/tabs, AppleScript for titles      |
| **Process Management**     | AppleScript for TTY, then system calls | Could use AX to identify session, then process APIs      |
| **Window Grouping**        | AppleScript to check all titles        | AX for window enumeration, AppleScript for title details |

## Performance Comparison

### AppleScript Performance

- **Pros**: Direct access to terminal properties, single call for complex operations
- **Cons**: Script compilation overhead, inter-process communication latency
- **Typical latency**: 50-200ms per operation

### Accessibility API Performance

- **Pros**: Direct API calls, no script compilation, faster for UI traversal
- **Cons**: Multiple API calls needed, requires UI element discovery
- **Typical latency**: 5-50ms per operation

## Reliability Comparison

### AppleScript Reliability

- **Pros**: Well-defined terminal dictionary, consistent behavior
- **Cons**: Can fail if UI is blocked, timing-sensitive operations
- **Error handling**: Good - specific error codes and messages

### Accessibility API Reliability

- **Pros**: More resilient to UI state changes, better async handling
- **Cons**: Dependent on AX tree structure, can break with app updates
- **Error handling**: Limited - generic error codes

## Implementation Recommendations

### 1. Keep AppleScript for Core Operations

The following must remain in AppleScript:

- Command execution (`do script`)
- Terminal output reading (`history`)
- Session creation with specific properties
- Custom title management

### 2. Replace with AX APIs for UI Operations

Consider replacing these operations:

- Window/tab enumeration for listing sessions
- Focus operations (window raise, tab selection)
- Application activation
- Checking busy state

### 3. Hybrid Approach for Session Management

```swift
// Example hybrid approach
class HybridTerminalControl {
    // Use AX to find windows quickly
    func findWindowsWithAX() -> [AXUIElement] {
        // AX API calls to enumerate windows
    }

    // Use AppleScript for terminal-specific properties
    func getSessionDetails(window: AXUIElement) -> SessionInfo {
        // AppleScript to get TTY, history, custom title
    }
}
```

### 4. Specific AX Attributes for Terminal Apps

#### Terminal.app AX Attributes

- `AXRole`: "AXWindow", "AXTab", "AXScrollArea"
- `AXTitle`: Window/tab title
- `AXChildren`: Tab groups and content
- `AXFocused`: Focus state
- `AXPosition`, `AXSize`: Window geometry
- Custom: `AXBusy` (terminal-specific)

#### iTerm2 AX Attributes

- Similar to Terminal.app but with additional:
- `AXDescription`: Session descriptions
- `AXIdentifier`: Unique session IDs
- Custom attributes for split panes

## Migration Strategy

### Phase 1: Non-Breaking Additions

1. Add AX-based window enumeration alongside AppleScript
2. Implement AX-based focus operations as alternative
3. Benchmark performance differences

### Phase 2: Gradual Replacement

1. Replace window/tab listing with AX APIs
2. Use AX for all focus operations
3. Keep AppleScript for command execution

### Phase 3: Optimization

1. Cache AX element references
2. Implement hybrid approaches for complex operations
3. Add fallback mechanisms

## Code Examples

### Window Enumeration with AX

```swift
func listWindowsUsingAX(for app: NSRunningApplication) -> [WindowInfo] {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var windowsValue: CFTypeRef?

    guard AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsValue
    ) == .success else { return [] }

    let windows = windowsValue as? [AXUIElement] ?? []
    return windows.compactMap { parseWindowInfo($0) }
}
```

### Send Keystroke with AX

```swift
func sendControlC(to element: AXUIElement) {
    let keyCode: CGKeyCode = 0x08 // 'c' key
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    event?.flags = .maskControl
    event?.post(tap: .cghidEventTap)
}
```

### Focus Tab with AX

```swift
func focusTab(_ tab: AXUIElement) {
    AXUIElementSetAttributeValue(tab, kAXFocusedAttribute as CFString, true as CFTypeRef)
    if let window = getParentWindow(of: tab) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
```

## Conclusion

While Accessibility APIs can replace many UI-related AppleScript operations with better performance, core terminal functionality like command execution and output reading must remain in AppleScript. A hybrid approach leveraging both APIs would provide the best balance of performance, reliability, and functionality.

### Recommended Approach

1. Continue using AppleScript for terminal-specific operations
2. Gradually introduce AX APIs for UI manipulation
3. Maintain fallback mechanisms for compatibility
4. Focus on operations where AX provides clear performance benefits (window enumeration, focus operations)
