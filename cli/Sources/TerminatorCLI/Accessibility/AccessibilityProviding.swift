import Foundation
@preconcurrency import ApplicationServices

/// Protocol defining accessibility operations needed by Terminator
protocol AccessibilityProviding {
    /// Find all windows for a given application
    func findWindows(for bundleIdentifier: String) async throws -> [AXUIElement]
    
    /// Find all tabs within a window
    func findTabs(in window: AXUIElement) async throws -> [AXUIElement]
    
    /// Get the title of a UI element
    func getTitle(of element: AXUIElement) async throws -> String?
    
    /// Get a custom attribute value
    func getAttribute(_ attribute: String, of element: AXUIElement) async throws -> Any?
    
    /// Focus a specific UI element
    func focusElement(_ element: AXUIElement) async throws
    
    /// Check if an element is busy (Terminal.app specific)
    func isElementBusy(_ element: AXUIElement) async throws -> Bool
    
    /// Activate an application by bundle ID
    func activateApplication(bundleID: String) async throws
    
    /// Raise a window to front
    func raiseWindow(_ window: AXUIElement) async throws
    
    /// Get the selected tab in a window
    func getSelectedTab(in window: AXUIElement) async throws -> AXUIElement?
    
    /// Set the selected tab in a window
    func setSelectedTab(_ tab: AXUIElement, in window: AXUIElement) async throws
    
    /// Get window ID for caching purposes
    func getWindowID(_ window: AXUIElement) async throws -> String?
    
    /// Check if accessibility is enabled
    func isAccessibilityEnabled() -> Bool
    
    /// Request accessibility permission
    func requestAccessibilityPermission() async throws
}

/// Errors that can occur during accessibility operations
enum AccessibilityError: LocalizedError {
    case permissionDenied
    case elementNotFound
    case attributeNotSupported(String)
    case actionFailed(String)
    case applicationNotRunning(String)
    case invalidElement
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission not granted"
        case .elementNotFound:
            return "UI element not found"
        case .attributeNotSupported(let attr):
            return "Attribute '\(attr)' not supported"
        case .actionFailed(let action):
            return "Action '\(action)' failed"
        case .applicationNotRunning(let bundleID):
            return "Application '\(bundleID)' is not running"
        case .invalidElement:
            return "Invalid UI element"
        }
    }
}

/// Cache for accessibility elements to improve performance
actor AXElementCache {
    private struct CacheEntry {
        let element: AXUIElement
        let timestamp: Date
    }
    
    private var windowCache: [String: CacheEntry] = [:]
    private var tabCache: [String: [AXUIElement]] = [:]
    private let cacheTimeout: TimeInterval = 2.0
    
    func getCachedWindow(id: String) -> AXUIElement? {
        guard let entry = windowCache[id],
              Date().timeIntervalSince(entry.timestamp) < cacheTimeout else {
            return nil
        }
        return entry.element
    }
    
    func cacheWindow(_ window: AXUIElement, id: String) {
        windowCache[id] = CacheEntry(element: window, timestamp: Date())
    }
    
    func getCachedTabs(windowID: String) -> [AXUIElement]? {
        guard let entry = windowCache[windowID],
              Date().timeIntervalSince(entry.timestamp) < cacheTimeout,
              let tabs = tabCache[windowID] else {
            return nil
        }
        return tabs
    }
    
    func cacheTabs(_ tabs: [AXUIElement], windowID: String) {
        tabCache[windowID] = tabs
    }
    
    func clearCache() {
        windowCache.removeAll()
        tabCache.removeAll()
    }
}