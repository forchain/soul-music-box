import Foundation
import ApplicationServices
import Yams

struct UIElementPath {
    let role: String
    let identifier: String?
    let className: String?
    let label: String?
    let index: Int?
    let matchType: MatchType
    let children: [UIElementPath]?
    
    init(role: String, 
         identifier: String? = nil, 
         className: String? = nil, 
         label: String? = nil, 
         index: Int? = nil, 
         matchType: MatchType = .contains, 
         children: [UIElementPath]? = nil) {
        self.role = role
        self.identifier = identifier
        self.className = className
        self.label = label
        self.index = index
        self.matchType = matchType
        self.children = children
    }
    
    var description: String {
        var desc = "Role: \(role)"
        if let id = identifier { desc += ", Identifier: \(id)" }
        if let cn = className { desc += ", Class: \(cn)" }
        if let lb = label { desc += ", Label: \(lb)" }
        if let idx = index { desc += ", Index: \(idx)" }
        desc += ", MatchType: \(matchType)"
        return desc
    }
}

enum MatchType: String, Codable {
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
        // 尝试多个可能的位置
        let possiblePaths = [
            // 1. 项目根目录
            FileManager.default.currentDirectoryPath + "/\(file).yaml",
            // 2. SoulMusicBox/Resources 目录
            Bundle.main.bundlePath + "/Contents/Resources/\(file).yaml",
            // 3. 开发时的项目目录
            Bundle.main.bundlePath + "/\(file).yaml"
        ]
        
        // logger.debug("Searching for config file in:")
        // for path in possiblePaths {
        //     logger.debug("- \(path)")
        // }
        
        guard let configPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logger.error("Config file not found in any of the possible locations")
            throw ConfigError.fileNotFound
        }
        
        do {
            let yamlString = try String(contentsOfFile: configPath, encoding: .utf8)
            logger.info("Successfully loaded config from: \(configPath)")
            
            // 使用 Yams 解析 YAML
            let decoder = YAMLDecoder()
            let configData = try decoder.decode([String: AppConfig].self, from: yamlString)
            
            // 转换为内部配置格式
            configs = configData.mapValues { config in
                AppUIConfig(
                    appName: config.name,
                    bundleId: config.bundleId,
                    elements: config.elements.mapValues { element in
                        convertToUIElementPath(from: element)
                    }
                )
            }
            
            logger.debug("Loaded configs for apps: \(configs.keys.joined(separator: ", "))")
        } catch {
            logger.error("Failed to parse config file: \(error)")
            throw ConfigError.invalidConfig
        }
    }
    
    private func convertToUIElementPath(from element: ElementConfig) -> UIElementPath {
        return UIElementPath(
            role: element.role,
            identifier: element.identifier,
            className: element.className,
            label: element.label,
            index: element.index,
            matchType: element.matchType ?? .contains,
            children: element.children?.map { convertToUIElementPath(from: $0) }
        )
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
        
        if result == .apiDisabled {
            logger.error("Accessibility API is disabled")
            throw ConfigError.accessibilityDisabled
        } else if result == .notImplemented {
            logger.error("Application does not support accessibility API")
            throw ConfigError.accessibilityNotSupported
        } else if result == .cannotComplete {
            logger.error("Cannot access application. Try removing and re-adding accessibility permissions")
            throw ConfigError.accessibilityCannotComplete
        } else if result != .success {
            logger.error("Failed to get children: \(result)")
            throw ConfigError.accessibilityError(result)
        }
        
        guard let children = childrenRef as? [AXUIElement] else {
            logger.error("No children found or invalid type")
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
        
        // 检查标识符
        if let identifier = path.identifier {
            var identifierRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
            guard let elementIdentifier = identifierRef as? String,
                  matchesString(elementIdentifier, pattern: identifier, type: path.matchType) else {
                return false
            }
        }
        
        // 检查类名
        if let className = path.className {
            var classRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXClassDescription" as CFString, &classRef)
            guard let elementClass = classRef as? String,
                  matchesString(elementClass, pattern: className, type: path.matchType) else {
                return false
            }
        }
        
        // 检查标签
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
    
    func getBundleId(for app: String) -> String? {
        logger.debug("Getting bundleId for app: \(app)")
        let bundleId = configs[app]?.bundleId
        logger.debug("Found bundleId: \(bundleId ?? "nil")")
        return bundleId
    }
}

enum ConfigError: Error {
    case fileNotFound
    case appConfigNotFound
    case elementPathNotFound
    case invalidConfig
    case accessibilityDisabled
    case accessibilityNotSupported
    case accessibilityCannotComplete
    case accessibilityError(AXError)
}

// YAML 配置解析模型
private struct AppConfig: Decodable {
    let bundleId: String
    var name: String { "" }  // 不从 YAML 中读取，使用默认值
    let elements: [String: ElementConfig]
    
    private enum CodingKeys: String, CodingKey {
        case bundleId, elements
    }
}

private struct ElementConfig: Decodable {
    let role: String
    let identifier: String?
    let className: String?
    let label: String?
    let index: Int?
    let matchType: MatchType?
    let children: [ElementConfig]?
    
    private enum CodingKeys: String, CodingKey {
        case role, identifier, className, label, index, matchType, children
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        role = try container.decode(String.self, forKey: .role)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        className = try container.decodeIfPresent(String.self, forKey: .className)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        matchType = try container.decodeIfPresent(MatchType.self, forKey: .matchType)
        children = try container.decodeIfPresent([ElementConfig].self, forKey: .children)
    }
} 