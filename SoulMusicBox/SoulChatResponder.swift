import Foundation
import Cocoa
import ApplicationServices

class SoulChatResponder {
    static let shared = SoulChatResponder()
    
    private let soulBundleId = "com.soul.macapp"
    private var soulApp: NSRunningApplication?
    private let finder = UIElementFinder.shared
    private let logger = Logger.shared
    
    private init() {}
    
    func sendMessage(_ message: String) {
        do {
            try activateSoulAndSendMessage(message)
        } catch {
            logger.error("Failed to send message to Soul: \(error)")
        }
    }
    
    private func activateSoulAndSendMessage(_ message: String) throws {
        // Find Soul application
        guard let app = NSWorkspace.shared.runningApplications.first(where: { app in
            app.bundleIdentifier == soulBundleId
        }) else {
            throw ChatError.appNotFound
        }
        
        soulApp = app
        
        // Activate Soul window
        app.activate(options: [])
        Thread.sleep(forTimeInterval: 0.5) // Wait for window activation
        
        // Get Soul window
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        // Find chat input box
        guard let inputBox = try findChatInputBox(in: appRef) else {
            throw ChatError.inputBoxNotFound
        }
        
        // Focus and input message
        try focusAndInput(element: inputBox, text: message)
        
        // Press return to send
        simulateKeyPress(key: 0x24) // Return key
    }
    
    private func findChatInputBox(in appRef: AXUIElement) throws -> AXUIElement? {
        return try finder.findElement(
            named: "chatInput",
            in: "Soul",
            parent: appRef
        )
    }
    
    private func focusAndInput(element: AXUIElement, text: String) throws {
        // Focus the element
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        
        // Set the value
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        if result != .success {
            throw ChatError.inputFailed
        }
    }
    
    private func simulateKeyPress(key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum ChatError: Error {
    case appNotFound
    case windowNotFound
    case inputBoxNotFound
    case inputFailed
} 