# AXorcist Integration Architecture for Terminator

## Overview

This document outlines the architecture for integrating AXorcist accessibility APIs into Terminator, enabling a hybrid approach that combines the performance benefits of accessibility APIs with the functionality of AppleScript.

## Architecture Design

### 1. Layered Approach

```
┌─────────────────────────────────────────────────────────────┐
│                    TerminalControlling Protocol              │
├─────────────────────────────────────────────────────────────┤
│                   HybridTerminalControl                      │
│  ┌─────────────────────────┐  ┌──────────────────────────┐ │
│  │   AXorcist Operations    │  │  AppleScript Operations  │ │
│  │  - Window enumeration    │  │  - Command execution     │ │
│  │  - Focus management      │  │  - Output reading        │ │
│  │  - UI navigation         │  │  - Session creation      │ │
│  │  - State checking        │  │  - TTY/process info      │ │
│  └─────────────────────────┘  └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 2. Integration Points

#### A. Package Dependencies

Add AXorcist to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    .package(url: "https://github.com/steipete/AXorcist.git", from: "1.0.0")
],
targets: [
    .executableTarget(
        name: "TerminatorCLI",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "AXorcist", package: "AXorcist"),
            "CResponsibility"
        ]
    )
]
```

#### B. New Protocol Layer

Create `AccessibilityProviding` protocol:

```swift
protocol AccessibilityProviding {
    func findWindows(for appIdentifier: String) async throws -> [AXUIElement]
    func findTabs(in window: AXUIElement) async throws -> [AXUIElement]
    func getTitle(of element: AXUIElement) async throws -> String?
    func focusElement(_ element: AXUIElement) async throws
    func isElementBusy(_ element: AXUIElement) async throws -> Bool
    func activateApplication(bundleID: String) async throws
}
```

#### C. Hybrid Controller Implementation

```swift
class HybridTerminalControl: TerminalControlling {
    private let axProvider: AccessibilityProviding
    private let scriptBridge: AppleScriptBridge
    private let terminalType: TerminalType

    enum TerminalType {
        case appleTerminal(bundleID: String = "com.apple.Terminal")
        case iTerm(bundleID: String = "com.googlecode.iterm2")
        case ghosty(bundleID: String = "com.mitchellh.ghostty")
    }

    // Use AX for UI operations, AppleScript for terminal-specific operations
    func listSessions(filterByTag: String?) async throws -> [TerminalSessionInfo] {
        // 1. Use AXorcist to enumerate windows and tabs
        let windows = try await axProvider.findWindows(for: terminalType.bundleID)

        // 2. Extract session info from tab titles using AX
        var sessions: [TerminalSessionInfo] = []
        for window in windows {
            let tabs = try await axProvider.findTabs(in: window)
            for tab in tabs {
                if let title = try await axProvider.getTitle(of: tab),
                   let sessionInfo = parseSessionInfo(from: title) {
                    sessions.append(sessionInfo)
                }
            }
        }

        // 3. Use AppleScript only for TTY/process info if needed
        return sessions
    }
}
```

### 3. Migration Strategy

#### Phase 1: Infrastructure Setup

1. Add AXorcist dependency
2. Create `AccessibilityProviding` protocol and implementation
3. Add permission checks for Accessibility alongside AppleEvents
4. Create `HybridTerminalControl` base class

#### Phase 2: UI Operations Migration

1. Window enumeration → AXorcist
2. Tab enumeration → AXorcist
3. Focus operations → AXorcist
4. Application activation → AXorcist
5. Busy state checking → AXorcist (where supported)

#### Phase 3: Hybrid Implementation

1. Keep AppleScript for:
   - Command execution (`do script`)
   - Output/history reading
   - Session creation
   - TTY device paths
   - Process group IDs

2. Use AXorcist for:
   - All UI navigation
   - Window/tab discovery
   - Focus management
   - State monitoring

#### Phase 4: Terminal-Specific Optimizations

1. Apple Terminal: Use AX `AXBusy` attribute
2. iTerm: Combine AX for UI + AppleScript for `write text`
3. Ghosty: Evaluate AX support quality

### 4. Performance Optimization

#### Caching Strategy

```swift
class AXElementCache {
    private var windowCache: [String: (element: AXUIElement, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 2.0

    func getCachedWindow(id: String) -> AXUIElement? {
        guard let cached = windowCache[id],
              Date().timeIntervalSince(cached.timestamp) < cacheTimeout else {
            return nil
        }
        return cached.element
    }
}
```

#### Concurrent Operations

```swift
func listAllSessions() async throws -> [TerminalSessionInfo] {
    // Parallel window enumeration
    async let terminalSessions = listTerminalSessions()
    async let iTermSessions = listITermSessions()

    return try await terminalSessions + iTermSessions
}
```

### 5. Error Handling

#### Permission Handling

```swift
enum PermissionError: Error {
    case appleEventsNotGranted(bundleID: String)
    case accessibilityNotGranted
    case bothPermissionsRequired
}

func checkPermissions() throws {
    let hasAppleEvents = AppleScriptBridge.hasPermission(for: bundleID)
    let hasAccessibility = AXIsProcessTrusted()

    if !hasAppleEvents && !hasAccessibility {
        throw PermissionError.bothPermissionsRequired
    }
}
```

#### Fallback Mechanism

```swift
func executeOperation() async throws -> Result {
    do {
        // Try AX first for performance
        return try await performViaAccessibility()
    } catch {
        Logger.log(level: .debug, "AX operation failed, falling back to AppleScript")
        return try performViaAppleScript()
    }
}
```

### 6. Testing Strategy

#### Unit Tests

- Mock `AccessibilityProviding` for isolated testing
- Test permission handling logic
- Verify fallback mechanisms

#### Integration Tests

- Test hybrid operations against real terminals
- Verify performance improvements
- Ensure feature parity with AppleScript-only approach

#### Performance Benchmarks

```swift
func benchmarkWindowEnumeration() async throws {
    let appleScriptTime = try await measureTime {
        try listWindowsViaAppleScript()
    }

    let axorcistTime = try await measureTime {
        try await listWindowsViaAXorcist()
    }

    print("AppleScript: \(appleScriptTime)ms, AXorcist: \(axorcistTime)ms")
}
```

### 7. Configuration

Add new environment variables:

```bash
TERMINATOR_USE_ACCESSIBILITY=true  # Enable hybrid mode
TERMINATOR_AX_CACHE_TIMEOUT=2.0   # Cache timeout in seconds
TERMINATOR_AX_FALLBACK=true       # Enable AppleScript fallback
```

### 8. Benefits of This Architecture

1. **Performance**: 5-10x faster for UI operations
2. **Reliability**: Fallback ensures functionality
3. **Maintainability**: Clear separation of concerns
4. **Future-proof**: Can gradually shift more to AX as APIs improve
5. **Compatibility**: Works with existing AppleScript infrastructure

### 9. Risks and Mitigations

| Risk                   | Mitigation                                  |
| ---------------------- | ------------------------------------------- |
| AX API limitations     | Keep AppleScript for unsupported operations |
| Permission complexity  | Clear user guidance, automatic prompts      |
| Breaking changes       | Comprehensive test suite                    |
| Performance regression | Benchmarking, selective migration           |

### 10. Implementation Timeline

- **Week 1-2**: Infrastructure setup, AXorcist integration
- **Week 3-4**: Migrate UI operations to AX
- **Week 5-6**: Implement hybrid controllers
- **Week 7-8**: Testing, benchmarking, optimization
- **Week 9-10**: Documentation, rollout strategy

This architecture provides a pragmatic path forward that leverages AXorcist's performance benefits while maintaining Terminator's full functionality through strategic use of AppleScript where necessary.
