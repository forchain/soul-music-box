import Cocoa
import ApplicationServices

class MessageMonitor {
    static let shared = MessageMonitor()
    
    private var soulApp: NSRunningApplication?
    private var observer: AXObserver?
    private var lastProcessedMessage: String?
    private let finder = UIElementFinder.shared
    private let logger = Logger.shared
    
    private init() {
        setupAccessibility()
    }
    
    private func setupAccessibility() {
        guard AXIsProcessTrustedWithOptions(nil) else {
            logger.error("Please enable Accessibility permissions for this app")
            return
        }
    }
    
    func startMonitoring() {
        // Get Soul bundle ID from config
        guard let bundleId = finder.getBundleId(for: "Soul") else {
            logger.error("Failed to get Soul bundle ID from config")
            return
        }
        
        // Find Soul application
        guard let app = NSWorkspace.shared.runningApplications.first(where: { app in
            app.bundleIdentifier == bundleId
        }) else {
            logger.error("Soul app is not running")
            return
        }
        
        soulApp = app
        
        // Create accessibility observer
        var observer: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { (observer, element, notification, refcon) in
            MessageMonitor.shared.handleChatUpdate(element: element)
        }, &observer)
        
        guard result == .success, let observer = observer else {
            logger.error("Failed to create accessibility observer")
            return
        }
        
        self.observer = observer
        
        // Get Soul main window and chat area
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        // Find the chat messages area
        findChatMessagesArea(in: appRef)
        
        // Add observer for chat content changes
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                          AXObserverGetRunLoopSource(observer),
                          .defaultMode)
    }
    
    private func findChatMessagesArea(in appRef: AXUIElement) {
        // Get all windows
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard let windows = windowsRef as? [AXUIElement] else { return }
        
        for window in windows {
            // Get window title
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            
            if let title = titleRef as? String {
                // Look for chat window (adjust title based on Soul's UI)
                if title.contains("聊天") || title.contains("Chat") {
                    findMessagesScrollArea(in: window)
                }
            }
        }
    }
    
    private func findMessagesScrollArea(in window: AXUIElement) {
        // Get all scroll areas in the window
        var scrollAreasRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXScrollAreas" as CFString, &scrollAreasRef)
        
        guard let scrollAreas = scrollAreasRef as? [AXUIElement] else { return }
        
        for scrollArea in scrollAreas {
            // Add observer for this scroll area
            AXObserverAddNotification(observer!,
                                    scrollArea,
                                    kAXValueChangedNotification as CFString,
                                    nil)
            
            // Also monitor for new messages
            AXObserverAddNotification(observer!,
                                    scrollArea,
                                    kAXRowCountChangedNotification as CFString,
                                    nil)
            
            // Get the messages table/list
            findMessagesContent(in: scrollArea)
        }
    }
    
    private func findMessagesContent(in scrollArea: AXUIElement) {
        // Get the content of the scroll area
        var contentRef: CFTypeRef?
        AXUIElementCopyAttributeValue(scrollArea, kAXContentsAttribute as CFString, &contentRef)
        
        guard let contents = contentRef as? [AXUIElement] else { return }
        
        for content in contents {
            // Check if this is a table or list of messages
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(content, kAXRoleAttribute as CFString, &roleRef)
            
            if let role = roleRef as? String,
               (role == "AXTable" || role == "AXList") {
                // Monitor this element for changes
                AXObserverAddNotification(observer!,
                                        content,
                                        kAXValueChangedNotification as CFString,
                                        nil)
            }
        }
    }
    
    private func handleChatUpdate(element: AXUIElement) {
        // Get the role of the updated element
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        
        guard let role = roleRef as? String else { return }
        
        // Handle different types of UI elements
        switch role {
        case "AXStaticText", "AXTextArea":
            handleTextUpdate(element)
        case "AXRow", "AXCell":
            handleMessageRowUpdate(element)
        default:
            break
        }
    }
    
    private func handleTextUpdate(_ element: AXUIElement) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element,
                                                 kAXValueAttribute as CFString,
                                                 &value)
        
        guard result == .success,
              let stringValue = value as? String,
              stringValue != lastProcessedMessage else {
            return
        }
        
        lastProcessedMessage = stringValue
        processMessage(stringValue)
    }
    
    private func handleMessageRowUpdate(_ element: AXUIElement) {
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard let children = childrenRef as? [AXUIElement] else { return }
        
        // Look for text content in the message row
        for child in children {
            var valueRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef)
            
            if let message = valueRef as? String,
               message != lastProcessedMessage {
                lastProcessedMessage = message
                processMessage(message)
            }
        }
    }
    
    func processMessage(_ message: String) {
        let parser = MessageParser()
        if let playCommand = parser.parsePlayCommand(message) {
            do {
                try QQMusicController.shared.playMusic(song: playCommand.song,
                                                     artist: playCommand.artist)
            } catch {
                logger.error("Failed to play music: \(error)")
            }
        }
    }
    
    func stopMonitoring() {
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                                AXObserverGetRunLoopSource(observer),
                                .defaultMode)
        }
        observer = nil
        soulApp = nil
    }
}

// Error handling
extension MessageMonitor {
    enum MonitorError: Error {
        case accessibilityNotEnabled
        case appNotRunning
        case observerCreationFailed
    }
} 