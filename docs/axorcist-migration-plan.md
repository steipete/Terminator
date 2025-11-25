# AXorcist Migration Plan for Terminator

## Executive Summary

This plan outlines a phased migration from AppleScript to AXorcist accessibility APIs in Terminator. The migration follows a hybrid approach, maintaining AppleScript for terminal-specific operations while leveraging AXorcist for UI automation, resulting in significant performance improvements without sacrificing functionality.

## Migration Phases

### Phase 0: Preparation and Setup (Week 1-2)

#### Objectives
- Set up development environment
- Establish testing baseline
- Create migration infrastructure

#### Tasks
1. **Add AXorcist Dependency**
   ```swift
   // In Package.swift
   .package(url: "https://github.com/steipete/AXorcist.git", from: "1.0.0")
   ```

2. **Create Performance Baseline**
   - Benchmark current AppleScript operations
   - Document response times for each operation type
   - Create automated performance test suite

3. **Permission Infrastructure**
   - Update permission checks to include Accessibility
   - Create unified permission request flow
   - Update documentation for users

4. **Create Migration Flags**
   ```swift
   struct MigrationConfig {
       static let useAXForWindowEnum = ProcessInfo.processInfo.environment["TERMINATOR_AX_WINDOWS"] == "true"
       static let useAXForFocus = ProcessInfo.processInfo.environment["TERMINATOR_AX_FOCUS"] == "true"
       // ... other flags
   }
   ```

#### Deliverables
- [ ] AXorcist integrated into build
- [ ] Performance baseline documented
- [ ] Permission handling updated
- [ ] Feature flags implemented

### Phase 1: Window and Tab Enumeration (Week 3-4)

#### Objectives
- Replace AppleScript window/tab listing with AXorcist
- Maintain exact same output format
- Improve performance by 5-10x

#### Implementation

1. **Create AX Window Enumerator**
   ```swift
   class AXWindowEnumerator {
       func listWindows(for bundleID: String) async throws -> [WindowInfo] {
           let query = QueryCommand(
               appIdentifier: bundleID,
               locator: AXLocator(criteria: [
                   AXCriterion(attribute: "AXRole", value: "AXWindow")
               ])
           )
           // Implementation
       }
   }
   ```

2. **Implement Parallel Processing**
   - Enumerate all windows concurrently
   - Extract tab information in parallel
   - Cache results for rapid re-queries

3. **Create Fallback Mechanism**
   ```swift
   func listSessions() async throws -> [TerminalSessionInfo] {
       if MigrationConfig.useAXForWindowEnum {
           do {
               return try await listSessionsViaAX()
           } catch {
               Logger.log(level: .warn, "AX enumeration failed: \(error)")
               return try listSessionsViaAppleScript()
           }
       }
       return try listSessionsViaAppleScript()
   }
   ```

#### Testing
- [ ] Unit tests for AX enumerator
- [ ] Integration tests with all terminal apps
- [ ] Performance comparison tests
- [ ] Fallback mechanism tests

#### Success Metrics
- Window enumeration < 50ms (from ~200ms)
- 100% feature parity
- Zero regression in reliability

### Phase 2: Focus and Activation Operations (Week 5-6)

#### Objectives
- Migrate focus operations to AXorcist
- Improve responsiveness of session switching
- Reduce terminal app disruption

#### Implementation

1. **AX Focus Manager**
   ```swift
   class AXFocusManager {
       func focusWindow(_ windowID: String) async throws {
           // Find window element
           let window = try await findWindow(id: windowID)
           
           // Perform focus actions
           try await performAction(window, action: kAXRaiseAction)
           try await setFrontmost(window)
       }
       
       func focusTab(_ tabID: String, in windowID: String) async throws {
           // Implementation
       }
   }
   ```

2. **Smart Activation**
   - Only activate app if not already frontmost
   - Minimize window state changes
   - Preserve user's current focus when possible

3. **Update Controllers**
   - Modify `AppleTerminalControl.focusSession()`
   - Modify `ITermControl.focusSession()`
   - Add performance logging

#### Testing
- [ ] Focus accuracy tests
- [ ] Multi-monitor support
- [ ] Minimized window handling
- [ ] User disruption measurements

#### Success Metrics
- Focus operations < 20ms
- Reduced app activation by 50%
- No focus-stealing complaints

### Phase 3: State Monitoring (Week 7)

#### Objectives
- Use AX for busy state checking
- Implement efficient polling mechanisms
- Reduce AppleScript overhead

#### Implementation

1. **Busy State Monitor**
   ```swift
   class AXBusyStateMonitor {
       func isTabBusy(_ tab: AXUIElement) async throws -> Bool {
           // Check AXBusy attribute for Terminal.app
           if let busy = try? tab.getAttribute("AXBusy") as? Bool {
               return busy
           }
           // Fallback for other terminals
           return try await checkBusyViaAppleScript()
       }
   }
   ```

2. **Efficient Polling**
   - Use AX observers for state changes
   - Implement exponential backoff
   - Cache state for short periods

#### Testing
- [ ] Busy detection accuracy
- [ ] Performance under load
- [ ] Observer reliability

### Phase 4: Hybrid Controller Implementation (Week 8-9)

#### Objectives
- Create unified hybrid controllers
- Seamless integration of AX and AppleScript
- Maintain backwards compatibility

#### Implementation

1. **Base Hybrid Controller**
   ```swift
   class HybridTerminalControlBase: TerminalControlling {
       let axProvider: AXorcistProvider
       let scriptBridge: AppleScriptBridge
       
       // Override specific methods to use AX
       func listSessions(filterByTag: String?) async throws -> [TerminalSessionInfo] {
           // AX implementation
       }
       
       // Keep AppleScript for these
       func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
           // AppleScript implementation
       }
   }
   ```

2. **Terminal-Specific Implementations**
   - `HybridAppleTerminalControl`
   - `HybridITermControl`
   - `HybridGhostyControl` (if AX support exists)

3. **Controller Factory Update**
   ```swift
   func createController(for app: String) -> TerminalControlling {
       if FeatureFlags.useHybridMode {
           return createHybridController(for: app)
       }
       return createLegacyController(for: app)
   }
   ```

#### Testing
- [ ] Full regression test suite
- [ ] Performance benchmarks
- [ ] Memory usage analysis
- [ ] Error handling validation

### Phase 5: Optimization and Polish (Week 10)

#### Objectives
- Performance tuning
- Documentation updates
- Production readiness

#### Tasks

1. **Performance Optimization**
   - Profile hot paths
   - Implement smart caching
   - Optimize AX query patterns

2. **Documentation**
   - Update README with new requirements
   - Document performance improvements
   - Create migration guide for users

3. **Monitoring and Metrics**
   - Add performance metrics logging
   - Create dashboard for operation timings
   - Set up alerts for degradation

4. **Final Testing**
   - Load testing with many windows/tabs
   - Long-running stability tests
   - User acceptance testing

## Rollout Strategy

### Gradual Rollout

1. **Alpha Phase** (Internal Testing)
   - Enable for development team
   - Collect performance metrics
   - Fix critical issues

2. **Beta Phase** (Opt-in)
   - Add `TERMINATOR_EXPERIMENTAL_AX=true` flag
   - Document in README
   - Collect user feedback

3. **General Availability**
   - Enable by default
   - Keep fallback for 2-3 releases
   - Monitor error rates

### Rollback Plan

If critical issues arise:
1. Immediate: Disable via feature flag
2. Hot fix: Revert to AppleScript-only
3. Communication: Alert users of known issues

## Success Metrics

### Performance Targets
| Operation | Current (AppleScript) | Target (AXorcist) | Improvement |
|-----------|----------------------|-------------------|-------------|
| List Windows | 200ms | 20ms | 10x |
| Focus Session | 150ms | 15ms | 10x |
| Check Busy | 100ms | 10ms | 10x |
| Activate App | 300ms | 30ms | 10x |

### Quality Metrics
- Error rate < 0.1% (same as current)
- No regression in functionality
- User satisfaction maintained/improved

### Technical Metrics
- Code coverage > 90%
- Memory usage stable
- CPU usage reduced by 50%

## Risk Management

### Technical Risks

1. **AX API Limitations**
   - *Risk*: Some operations may not be possible
   - *Mitigation*: Maintain AppleScript fallback
   - *Impact*: Low - hybrid approach ensures functionality

2. **Permission Complexity**
   - *Risk*: Users confused by dual permissions
   - *Mitigation*: Clear documentation, unified flow
   - *Impact*: Medium - one-time setup issue

3. **Terminal App Updates**
   - *Risk*: AX structure changes break integration
   - *Mitigation*: Version detection, graceful degradation
   - *Impact*: Low - affects only new versions

### Schedule Risks

1. **AXorcist API Learning Curve**
   - *Buffer*: Added 1 week to Phase 1
   - *Mitigation*: Early prototyping

2. **Testing Complexity**
   - *Buffer*: Dedicated testing phases
   - *Mitigation*: Automated test suite

## Long-term Vision

### Future Enhancements

1. **Year 1**: 
   - Complete hybrid implementation
   - 80% operations via AX
   
2. **Year 2**:
   - Explore replacing more AppleScript operations
   - Investigate direct Terminal.app API access
   
3. **Year 3**:
   - Potentially eliminate AppleScript entirely
   - Native performance throughout

### Maintenance Plan

- Quarterly performance reviews
- Continuous optimization
- Stay updated with AX API changes
- Community feedback integration

## Conclusion

This migration plan provides a low-risk, high-reward path to modernizing Terminator's terminal interaction layer. By taking a hybrid approach and migrating incrementally, we can achieve significant performance improvements while maintaining the reliability users expect.

The phased approach allows for careful validation at each step, with clear rollback procedures if issues arise. The end result will be a faster, more responsive Terminator that leverages modern macOS APIs while retaining full functionality.