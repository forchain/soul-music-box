import Foundation
import SwiftUI

class Logger {
    static let shared = Logger()
    
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case error = "ERROR"
    }
    
    var logCallback: ((Level, String) -> Void)?
    
    func log(_ message: String, level: Level = .info, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)"
        print(logMessage)
        
        logCallback?(level, message)
    }
    
    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }
    
    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }
    
    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }
} 