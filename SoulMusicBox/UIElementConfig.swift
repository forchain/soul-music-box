import Foundation
import ApplicationServices

struct UIElementPath {
    let role: String
    let identifier: String?
    let label: String?
    let index: Int?
    let matchType: MatchType
    let children: [UIElementPath]?
    
    init(role: String, 
         identifier: String? = nil, 
         label: String? = nil, 
         index: Int? = nil, 
         matchType: MatchType = .contains, 
         children: [UIElementPath]? = nil) {
        self.role = role
        self.identifier = identifier
        self.label = label
        self.index = index
        self.matchType = matchType
        self.children = children
    }
    
    var description: String {
        var desc = "Role: \(role)"
        if let id = identifier { desc += ", Identifier: \(id)" }
        if let lb = label { desc += ", Label: \(lb)" }
        if let idx = index { desc += ", Index: \(idx)" }
        desc += ", MatchType: \(matchType)"
        return desc
    }
}

enum MatchType {
    case exact       // 精确匹配
    case contains    // 包含匹配
    case startsWith  // 前缀匹配
    case endsWith    // 后缀匹配
    case regex       // 正则匹配
}

struct AppUIConfig {
    let appName: String
    let bundleId: String
    let elements: [String: UIElementPath] // key is element name like "searchBox", "chatInput"
}

class UIElementFinder {
    static let shared = UIElementFinder()
    private var configs: [String: AppUIConfig] = [:]
    private let logger = Logger.shared
    
    func loadConfig(from file: String) throws {
        guard let url = Bundle.main.url(forResource: file, withExtension: "yaml") else {
            throw ConfigError.fileNotFound
        }
        
        do {
            // 使用新的 API 读取文件内容
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            // TODO: Parse YAML and update configs
            // You'll need to add a YAML parsing library like Yams
            // configs = try YAMLDecoder().decode([String: AppUIConfig].self, from: yamlString)
            _ = yamlString // 暂时使用这个变量以避免警告
        } catch {
            logger.error("Failed to read config file: \(error)")
            throw ConfigError.fileNotFound
        }
    }
    
    func findElement(named elementName: String, in app: String, parent: AXUIElement) throws -> AXUIElement? {
        guard let appConfig = configs[app] else {
            logger.error("No configuration found for app: \(app)")
            throw ConfigError.appConfigNotFound
        }
        
        guard let elementPath = appConfig.elements[elementName] else {
            logger.error("No element path found for: \(elementName) in app: \(app)")
            throw ConfigError.elementPathNotFound
        }
        
        return try findElement(following: elementPath, in: parent)
    }
    
    private func findElement(following path: UIElementPath, in parent: AXUIElement) throws -> AXUIElement? {
        logger.debug("Searching for element: \(path.description)")
        
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard result == .success,
              let children = childrenRef as? [AXUIElement] else {
            logger.error("Failed to get children for element: \(path.description)")
            return nil
        }
        
        logger.debug("Found \(children.count) children")
        
        // 找到所有匹配的元素
        var matchedElements: [AXUIElement] = []
        
        for child in children {
            if try matchesElement(element: child, path: path) {
                if let subPaths = path.children {
                    for subPath in subPaths {
                        if let found = try findElement(following: subPath, in: child) {
                            matchedElements.append(found)
                        }
                    }
                } else {
                    matchedElements.append(child)
                }
            }
            
            // 递归搜索子元素
            if let found = try findElement(following: path, in: child) {
                matchedElements.append(found)
            }
        }
        
        // 如果没有找到匹配元素，返回 nil
        if matchedElements.isEmpty {
            logger.debug("No matching elements found")
            return nil
        }
        
        // 处理索引
        if let idx = path.index {
            let actualIndex: Int
            if idx >= 0 {
                actualIndex = idx
            } else {
                actualIndex = matchedElements.count + idx // 负数从后往前数
            }
            
            guard actualIndex >= 0 && actualIndex < matchedElements.count else {
                logger.error("Index out of range: \(idx)")
                return nil
            }
            
            return matchedElements[actualIndex]
        }
        
        // 如果没有指定索引，返回第一个匹配的元素
        return matchedElements.first
    }
    
    private func matchesElement(element: AXUIElement, path: UIElementPath) throws -> Bool {
        // 检查角色
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard let elementRole = roleRef as? String, elementRole == path.role else {
            return false
        }
        
        // 检查标识符（Description）
        if let identifier = path.identifier {
            var descriptionRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionRef)
            guard let description = descriptionRef as? String,
                  matchesString(description, pattern: identifier, type: path.matchType) else {
                return false
            }
        }
        
        // 检查标签（Label）
        if let label = path.label {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            guard let title = titleRef as? String,
                  matchesString(title, pattern: label, type: path.matchType) else {
                return false
            }
        }
        
        return true
    }
    
    private func matchesString(_ string: String, pattern: String, type: MatchType) -> Bool {
        switch type {
        case .exact:
            return string == pattern
        case .contains:
            return string.contains(pattern)
        case .startsWith:
            return string.hasPrefix(pattern)
        case .endsWith:
            return string.hasSuffix(pattern)
        case .regex:
            return (try? NSRegularExpression(pattern: pattern)
                .firstMatch(in: string, range: NSRange(string.startIndex..., in: string))) != nil
        }
    }
}

enum ConfigError: Error {
    case fileNotFound
    case appConfigNotFound
    case elementPathNotFound
    case invalidConfig
} 