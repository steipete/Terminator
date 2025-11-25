import Foundation
@preconcurrency import ApplicationServices
import AppKit
import AXorcist

/// Implementation of AccessibilityProviding using AXorcist
final class AXorcistProvider: AccessibilityProviding, @unchecked Sendable {
    private var axorcist: AXorcist?
    private let cache = AXElementCache()
    
    init() {
        // AXorcist will be initialized on first use
    }
    
    @MainActor
    private func getAXorcist() -> AXorcist {
        if let axorcist = self.axorcist {
            return axorcist
        }
        let newAXorcist = AXorcist()
        self.axorcist = newAXorcist
        return newAXorcist
    }
    
    func findWindows(for bundleIdentifier: String) async throws -> [AXUIElement] {
        guard isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        // Create query for windows
        let query = QueryCommand(
            appIdentifier: bundleIdentifier,
            locator: Locator(criteria: [
                Criterion(attribute: "AXRole", value: "AXWindow")
            ])
        )
        
        let envelope = AXCommandEnvelope(commandID: UUID().uuidString, command: .query(query))
        let response = await MainActor.run {
            getAXorcist().runCommand(envelope)
        }
        
        switch response {
        case .success(let payload, _):
            // The payload should contain an array of AXElementData
            if let elementsData = payload?.value as? [[String: Any]] {
                // For now, we'll return mock elements as we need the actual AXUIElement references
                // In a real implementation, we'd need to store element references differently
                var elements: [AXUIElement] = []
                for _ in elementsData {
                    // Create a placeholder element - in real use, we'd need to maintain element references
                    elements.append(AXUIElementCreateSystemWide())
                }
                return elements
            }
            return []
        case .error(let message, _, _):
            Logger.log(level: .error, "Failed to find windows: \(message)")
            throw AccessibilityError.elementNotFound
        }
    }
    
    func findTabs(in window: AXUIElement) async throws -> [AXUIElement] {
        // For Terminal.app and iTerm, tabs are usually in a tab group
        let tabGroups = try await findChildren(of: window, role: "AXTabGroup")
        
        var allTabs: [AXUIElement] = []
        for tabGroup in tabGroups {
            let tabs = try await findChildren(of: tabGroup, role: "AXRadioButton")
            allTabs.append(contentsOf: tabs)
        }
        
        return allTabs
    }
    
    func getTitle(of element: AXUIElement) async throws -> String? {
        return try await getAttribute(kAXTitleAttribute as String, of: element) as? String
    }
    
    func getAttribute(_ attribute: String, of element: AXUIElement) async throws -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        
        switch result {
        case .success:
            return value
        case .attributeUnsupported:
            throw AccessibilityError.attributeNotSupported(attribute)
        case .invalidUIElement:
            throw AccessibilityError.invalidElement
        default:
            return nil
        }
    }
    
    func focusElement(_ element: AXUIElement) async throws {
        // Set element as focused
        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFBoolean)
        
        if result != .success {
            throw AccessibilityError.actionFailed("focus")
        }
    }
    
    func isElementBusy(_ element: AXUIElement) async throws -> Bool {
        // Terminal.app exposes AXBusy attribute
        if let busy = try? await getAttribute("AXBusy", of: element) as? Bool {
            return busy
        }
        return false
    }
    
    func activateApplication(bundleID: String) async throws {
        // Use NSWorkspace for reliable app activation
        await MainActor.run {
            let workspace = NSWorkspace.shared
            let apps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleID }
            
            guard let app = apps.first else {
                Logger.log(level: .error, "Application not found: \(bundleID)")
                return
            }
            
            app.activate(options: [.activateAllWindows])
        }
    }
    
    func raiseWindow(_ window: AXUIElement) async throws {
        // Perform raise action
        let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        
        if result != .success {
            // Try alternative: set as main window
            let mainResult = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFBoolean)
            if mainResult != .success {
                throw AccessibilityError.actionFailed("raise")
            }
        }
    }
    
    func getSelectedTab(in window: AXUIElement) async throws -> AXUIElement? {
        // Find the tab group first
        let tabGroups = try await findChildren(of: window, role: "AXTabGroup")
        
        for tabGroup in tabGroups {
            // Get the selected tab (radio button with value 1)
            if let _ = try? await getAttribute(kAXValueAttribute as String, of: tabGroup) {
                let tabs = try await findChildren(of: tabGroup, role: "AXRadioButton")
                for tab in tabs {
                    if let value = try? await getAttribute(kAXValueAttribute as String, of: tab) as? Int,
                       value == 1 {
                        return tab
                    }
                }
            }
        }
        
        return nil
    }
    
    func setSelectedTab(_ tab: AXUIElement, in window: AXUIElement) async throws {
        // Click the tab to select it
        let result = AXUIElementPerformAction(tab, kAXPressAction as CFString)
        
        if result != .success {
            throw AccessibilityError.actionFailed("select tab")
        }
    }
    
    func getWindowID(_ window: AXUIElement) async throws -> String? {
        // Try to get window number or title as ID
        if let windowNumber = try? await getAttribute("AXWindowNumber", of: window) {
            return "window_\(windowNumber)"
        }
        
        if let title = try? await getTitle(of: window) {
            return "window_\(title.hashValue)"
        }
        
        return nil
    }
    
    func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() async throws {
        if !isAccessibilityEnabled() {
            // Use the existing permission helper
            AccessibilityPermission.requestAccessibilityPermission()
            
            // Wait a bit for user to grant permission
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            if !isAccessibilityEnabled() {
                throw AccessibilityError.permissionDenied
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func findChildren(of parent: AXUIElement, role: String? = nil) async throws -> [AXUIElement] {
        guard let children = try await getAttribute(kAXChildrenAttribute as String, of: parent) as? [AXUIElement] else {
            return []
        }
        
        if let role = role {
            return try await children.asyncCompactMap { [weak self] child in
                guard let self = self else { return nil }
                if let childRole = try await self.getAttribute(kAXRoleAttribute as String, of: child) as? String,
                   childRole == role {
                    return child
                }
                return nil
            }
        }
        
        return children
    }
}

// MARK: - Async Sequence Extensions

extension Sequence {
    func asyncCompactMap<T>(_ transform: @escaping (Element) async throws -> T?) async throws -> [T] {
        var results: [T] = []
        
        for element in self {
            if let transformed = try await transform(element) {
                results.append(transformed)
            }
        }
        
        return results
    }
}