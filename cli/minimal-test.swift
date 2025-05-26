import Foundation

// Test minimal functionality
print("Starting minimal test...")

// Test AppleScript execution
let script = """
tell application "Terminal"
    return "test"
end tell
"""

print("Running AppleScript...")
let appleScript = NSAppleScript(source: script)
var error: NSDictionary?
let result = appleScript?.executeAndReturnError(&error)

if let error = error {
    print("Error: \(error)")
} else {
    print("Result: \(String(describing: result))")
}

print("Test completed")