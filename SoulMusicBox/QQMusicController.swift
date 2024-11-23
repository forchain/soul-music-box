import Foundation
import Cocoa
import ApplicationServices

class QQMusicController {
    static let shared = QQMusicController()
    
    private let qqMusicBundleId = "com.tencent.QQMusicMac"
    private var qqMusicApp: NSRunningApplication?
    private let finder = UIElementFinder.shared
    private let logger = Logger.shared
    
    private init() {}
    
    func playMusic(song: String, artist: String?) throws {
        // Launch QQ Music if not running
        if qqMusicApp == nil || qqMusicApp!.isTerminated {
            // 使用新的 API 启动应用
            let config = NSWorkspace.OpenConfiguration()
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: qqMusicBundleId) else {
                throw MusicError.appLaunchFailed
            }
            
            NSWorkspace.shared.openApplication(at: appURL,
                                             configuration: config) { app, error in
                if let error = error {
                    self.logger.error("Failed to launch QQ Music: \(error)")
                }
            }
            
            // Get the running application after launch
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: qqMusicBundleId).first else {
                throw MusicError.appLaunchFailed
            }
            qqMusicApp = app
            Thread.sleep(forTimeInterval: 2) // Wait for app to initialize
        }
        
        // Get QQ Music window
        let appRef = AXUIElementCreateApplication(qqMusicApp!.processIdentifier)
        
        // Find main window
        guard let window = try findMainWindow(in: appRef) else {
            throw MusicError.windowNotFound
        }
        
        // Find and click search box
        guard let searchBox = try findSearchBox(in: window) else {
            throw MusicError.searchBoxNotFound
        }
        
        // Focus and input search term
        let searchTerm = artist != nil ? "\(song) \(artist!)" : song
        try focusAndInput(element: searchBox, text: searchTerm)
        
        // Wait for search results
        Thread.sleep(forTimeInterval: 1)
        
        // Find and click first result
        guard let firstResult = try findFirstSearchResult(in: window) else {
            throw MusicError.searchResultNotFound
        }
        
        // Find and click play button
        guard let playButton = try findPlayButton(in: firstResult) else {
            throw MusicError.playButtonNotFound
        }
        
        try clickElement(playButton)
        
        // After successful play, send response to Soul
        let response = "正在播放 \(artist ?? "未知歌手")《\(song)》"
        SoulChatResponder.shared.sendMessage(response)
    }
    
    private func findMainWindow(in appRef: AXUIElement) throws -> AXUIElement? {
        return try finder.findElement(
            named: "mainWindow",
            in: "QQMusic",
            parent: appRef
        )
    }
    
    private func findSearchBox(in window: AXUIElement) throws -> AXUIElement? {
        return try finder.findElement(
            named: "searchBox",
            in: "QQMusic",
            parent: window
        )
    }
    
    private func findFirstSearchResult(in window: AXUIElement) throws -> AXUIElement? {
        return try finder.findElement(
            named: "searchResults",
            in: "QQMusic",
            parent: window
        )
    }
    
    private func findPlayButton(in resultItem: AXUIElement) throws -> AXUIElement? {
        return try finder.findElement(
            named: "playButton",
            in: "QQMusic",
            parent: resultItem
        )
    }
    
    private func focusAndInput(element: AXUIElement, text: String) throws {
        // Focus the element
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        
        // Set the value
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        if result != .success {
            throw MusicError.inputFailed
        }
        
        // Press return to trigger search
        simulateKeyPress(key: 0x24) // Return key
    }
    
    private func clickElement(_ element: AXUIElement) throws {
        var position: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        
        guard result == .success,
              let point = position as? CGPoint else {
            throw MusicError.clickFailed
        }
        
        let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        
        clickDown?.post(tap: .cghidEventTap)
        clickUp?.post(tap: .cghidEventTap)
    }
    
    private func simulateKeyPress(key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum MusicError: Error {
    case appLaunchFailed
    case windowNotFound
    case searchBoxNotFound
    case searchResultNotFound
    case playButtonNotFound
    case inputFailed
    case clickFailed
} 