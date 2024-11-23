import Foundation

struct PlayCommand {
    let song: String
    let artist: String?
}

class MessageParser {
    func parsePlayCommand(_ message: String) -> PlayCommand? {
        // Check if message starts with "播放"
        guard message.hasPrefix("播放 ") else { return nil }
        
        // Remove "播放 " prefix and split remaining text
        let components = message.dropFirst(3).split(separator: " ")
        
        if components.count >= 1 {
            let song = String(components[0])
            let artist = components.count > 1 ? String(components[1]) : nil
            return PlayCommand(song: song, artist: artist)
        }
        
        return nil
    }
} 