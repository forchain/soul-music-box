//
//  ContentView.swift
//  SoulMusicBox
//
//  Created by Tony Outlier on 11/22/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    
    var body: some View {
        VStack {
            // 应用状态区域
            StatusSection(viewModel: viewModel)
            
            // 控件检查结果区域
            ElementCheckSection(viewModel: viewModel)
            
            // 日志区域
            LogSection(logs: viewModel.logs)
        }
        .padding()
        .onAppear {
            viewModel.checkAllElements()
        }
        .frame(width: 600)  // 设置一个固定宽度，避免窗口过大
    }
}

// 状态区域
struct StatusSection: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        GroupBox("应用状态") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusRow(title: "无障碍权限", isEnabled: viewModel.isAccessibilityEnabled)
                    Spacer()
                    if !viewModel.isAccessibilityEnabled {
                        Button(action: {
                            viewModel.showAccessibilityInstructions = true
                        }) {
                            Text("设置")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                        .sheet(isPresented: $viewModel.showAccessibilityInstructions) {
                            AccessibilityPermissionAlert(viewModel: viewModel)
                        }
                    }
                }
                StatusRow(title: "QQ音乐", isRunning: viewModel.isQQMusicRunning)
                StatusRow(title: "Soul", isRunning: viewModel.isSoulRunning)
            }
            .padding(.vertical, 5)
        }
    }
}

// 控件检查结果区域
struct ElementCheckSection: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        GroupBox("控件检查") {
            List {
                ForEach(viewModel.elementCheckResults) { result in
                    ElementCheckRow(result: result, viewModel: viewModel)
                }
            }
            .frame(height: 200)
        }
    }
}

// 日志区域
struct LogSection: View {
    let logs: [LogEntry]
    
    var body: some View {
        GroupBox("日志") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(logs) { log in
                            LogEntryView(log: log)
                                .id(log.id)  // 为每个日志条目添加 id
                        }
                    }
                }
                .onChange(of: logs.count) { _ in
                    // 当日志数量变化时，滚动到最后一条
                    if let lastLog = logs.last {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
            .frame(height: 150)
        }
    }
}

// 辅助视图组件
struct StatusRow: View {
    let title: String
    let isRunning: Bool
    
    init(title: String, isRunning: Bool = false, isEnabled: Bool = false) {
        self.title = title
        self.isRunning = isRunning || isEnabled
    }
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: isRunning ? "checkmark.circle.fill" : "x.circle.fill")
                .foregroundColor(isRunning ? .green : .red)
                .frame(width: 20, height: 20)  // 固定图标大小
        }
    }
}

struct ElementCheckRow: View {
    let result: ElementCheckResult
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(result.elementPath)
                Spacer()
                Button(action: {
                    generateUITree(for: result.elementPath)
                }) {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                Image(systemName: result.found ? "checkmark.circle.fill" : "x.circle.fill")
                    .foregroundColor(result.found ? .green : .red)
            }
            if !result.found {
                Text(result.error ?? "未找到控件")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private func generateUITree(for elementPath: String) {
        // 解析路径获取应用名和元素名
        let components = elementPath.split(separator: ".")
        guard components.count == 2,
              let app = components.first.map(String.init),
              let bundleId = viewModel.getBundleId(for: app) else {
            viewModel.logError("Invalid element path or app not found in config: \(elementPath)")
            return
        }
        
        // 获取应用进程
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { app in
            app.bundleIdentifier == bundleId
        }) else {
            viewModel.logError("Application not running: \(bundleId)")
            return
        }
        
        viewModel.logInfo("Generating UI tree for \(app) (pid: \(runningApp.processIdentifier))")
        
        // 生成 UI 树
        let appRef = AXUIElementCreateApplication(runningApp.processIdentifier)
        
        // 详细的权限检查
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXRoleAttribute as CFString, &value)
        
        if result == .apiDisabled {
            viewModel.logError("Accessibility API is disabled. Please enable it in System Preferences.")
            return
        } else if result == .notImplemented {
            viewModel.logError("Application does not support accessibility API.")
            return
        } else if result == .cannotComplete {
            viewModel.logError("Failed to access application. Try these steps:")
            viewModel.logError("1. Remove the app from accessibility list")
            viewModel.logError("2. Restart the app")
            viewModel.logError("3. Add the app back to accessibility list when prompted")
            viewModel.logError("4. If not prompted, manually add the app")
            return
        } else if result != .success {
            viewModel.logError("Unknown error accessing application: \(result)")
            return
        }
        
        viewModel.logInfo("Successfully accessed application root element")
        
        // 额外的权限验证
        var processAttrib: pid_t = 0
        let pidResult = AXUIElementGetPid(appRef, &processAttrib)
        if pidResult != .success {
            viewModel.logError("Failed to get process ID: \(pidResult)")
            return
        }
        
        if processAttrib != runningApp.processIdentifier {
            viewModel.logError("Process ID mismatch. Expected: \(runningApp.processIdentifier), Got: \(processAttrib)")
            return
        }
        
        viewModel.logInfo("Process ID verification passed")
        
        // 生成 UI 树
        let uiTree = viewModel.generateUITree(for: appRef)
        if uiTree.isEmpty {
            viewModel.logError("Failed to generate UI tree: no elements found")
            return
        }
        
        // 生成 YAML
        let yaml = """
        \(app):
          bundleId: "\(bundleId)"
          elements:
        \(uiTree.indented(by: 4))
        """
        
        // 保存到文件
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "\(app)_UITree_\(timestamp).yaml"
        
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(filename)
            do {
                try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
                viewModel.logInfo("UI tree saved to: \(fileURL.path)")
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
            } catch {
                viewModel.logError("Failed to save UI tree: \(error)")
            }
        }
    }
}

struct LogEntryView: View {
    let log: LogEntry
    
    var body: some View {
        Text("\(log.timestamp.formatted()) [\(log.level.rawValue)] \(log.message)")
            .font(.caption)
            .foregroundColor(log.level.color)
    }
}

// 数据模型
class ContentViewModel: ObservableObject {
    @Published var isQQMusicRunning = false
    @Published var isSoulRunning = false
    @Published var isAccessibilityEnabled = false
    @Published var elementCheckResults: [ElementCheckResult] = []
    @Published var logs: [LogEntry] = []
    @Published var showAccessibilityInstructions = false
    
    let finder = UIElementFinder.shared
    let logger = Logger.shared
    
    init() {
        setupLoggerCallback()
        loadConfigAndCheckStatus()
    }
    
    private func setupLoggerCallback() {
        logger.logCallback = { [weak self] level, message in
            DispatchQueue.main.async {
                self?.logs.append(LogEntry(level: level, message: message))
            }
        }
    }
    
    private func loadConfigAndCheckStatus() {
        do {
            try finder.loadConfig(from: "ui_config")
            checkApplicationStatus()
        } catch {
            logger.error("Failed to load config: \(error)")
        }
    }
    
    func checkApplicationStatus() {
        isAccessibilityEnabled = AXIsProcessTrustedWithOptions(nil)
        
        // 从配置中获取 bundleId
        if let qqMusicBundleId = finder.getBundleId(for: "QQMusic") {
            isQQMusicRunning = NSWorkspace.shared.runningApplications.contains { app in
                app.bundleIdentifier == qqMusicBundleId
            }
        }
        
        if let soulBundleId = finder.getBundleId(for: "Soul") {
            isSoulRunning = NSWorkspace.shared.runningApplications.contains { app in
                app.bundleIdentifier == soulBundleId
            }
        }
    }
    
    func checkAllElements() {
        // 不再重复加载配置
        if isQQMusicRunning {
            try? checkQQMusicElements()
        }
        
        if isSoulRunning {
            try? checkSoulElements()
        }
    }
    
    private func checkQQMusicElements() throws {
        guard let bundleId = finder.getBundleId(for: "QQMusic"),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            logger.error("QQ音乐未运行")
            return
        }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        try checkElement(named: "searchBox", in: "QQMusic", parent: appRef)
        try checkElement(named: "searchResults", in: "QQMusic", parent: appRef)
    }
    
    private func checkSoulElements() throws {
        guard let bundleId = finder.getBundleId(for: "Soul"),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            logger.error("Soul未运行")
            return
        }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        try checkElement(named: "chatInput", in: "Soul", parent: appRef)
        try checkElement(named: "chatHistory", in: "Soul", parent: appRef)
    }
    
    private func checkElement(named name: String, in app: String, parent: AXUIElement) throws {
        do {
            let element = try finder.findElement(named: name, in: app, parent: parent)
            let result = ElementCheckResult(
                elementPath: "\(app).\(name)",
                found: element != nil,
                error: element == nil ? "未找到控件" : nil
            )
            DispatchQueue.main.async {
                self.elementCheckResults.append(result)
            }
        } catch {
            let result = ElementCheckResult(
                elementPath: "\(app).\(name)",
                found: false,
                error: error.localizedDescription
            )
            DispatchQueue.main.async {
                self.elementCheckResults.append(result)
            }
        }
    }
    
    func getBundleId(for app: String) -> String? {
        return finder.getBundleId(for: app)
    }
    
    func logInfo(_ message: String) {
        logger.info(message)
    }
    
    func logError(_ message: String) {
        logger.error(message)
    }
    
    func generateUITree(for element: AXUIElement) -> String {
        var tree = ""
        
        // 获取元素角色
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        
        guard result == .success,
              let role = roleRef as? String else {
            logger.error("Failed to get role for element")
            return ""
        }
        
        logger.debug("Found element with role: \(role)")
        tree += "role: \"\(role)\"\n"
        
        // 获取元素标识符
        var identifierRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
        if let identifier = identifierRef as? String {
            logger.debug("  identifier: \(identifier)")
            tree += "identifier: \"\(identifier)\"\n".indented(by: 0)
        }
        
        // 获取类名
        var classRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXClassDescription" as CFString, &classRef)
        if let className = classRef as? String {
            logger.debug("  className: \(className)")
            tree += "className: \"\(className)\"\n".indented(by: 0)
        }
        
        // 获取元素标签
        var labelRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &labelRef)
        if let label = labelRef as? String {
            logger.debug("  label: \(label)")
            tree += "label: \"\(label)\"\n".indented(by: 0)
        }
        
        // 获取子元素
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement], !children.isEmpty {
            logger.debug("  found \(children.count) children")
            tree += "children:\n"
            for (index, child) in children.enumerated() {
                logger.debug("  processing child \(index)")
                tree += "- # index: \(index)\n".indented(by: 2)
                let childTree = generateUITree(for: child)
                if !childTree.isEmpty {
                    tree += childTree.indented(by: 4)
                }
            }
        }
        
        return tree
    }
}

// 模型
struct ElementCheckResult: Identifiable {
    let id = UUID()
    let elementPath: String
    let found: Bool
    let error: String?
    
    init(elementPath: String, found: Bool, error: String? = nil) {
        self.elementPath = elementPath
        self.found = found
        self.error = error
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let level: Logger.Level
    let message: String
}

extension Logger.Level {
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .primary
        case .error: return .red
        }
    }
}

struct AccessibilityPermissionAlert: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack(spacing: 10) {
            // 标题栏
            HStack {
                Text("需要无障碍权限")
                    .font(.headline)
                Spacer()
                Button(action: {
                    dismiss()
                    viewModel.checkApplicationStatus()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
            }
            .padding(.bottom)
            
            Text("请按以下步骤开启权限：")
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 5) {
                Text("1. 打开 系统偏好设置 > 安全性与隐私 > 隐私 > 辅助功能")
                Text("2. 点击左下角锁图标解锁")
                Text("3. 点击 + 号添加应用")
                Text("4. 在 Finder 中前往以下路径：")
                Text("   \(Bundle.main.bundlePath)")
                    .foregroundColor(.blue)
                    .textSelection(.enabled)  // 许用户选择和复制路径
                Text("5. 选择该应用并授权")
                Text("6. 重启应用以使权限生效")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // 底部按钮
            Button(action: {
                dismiss()
                viewModel.checkApplicationStatus()
            }) {
                Text("我已完成设置")
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            .padding(.top)
            
            // Finder按钮
            Button(action: {
                NSWorkspace.shared.selectFile(Bundle.main.bundlePath, 
                                            inFileViewerRootedAtPath: "")
            }) {
                Text("在 Finder 中显示应用")
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            .padding(.top, 5)
        }
        .padding()
        .frame(width: 500)
    }
}

struct PlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())  // 确保整个区域可点击
            .opacity(configuration.isPressed ? 0.7 : 1.0)  // 点击时的反馈效果
    }
}

#Preview {
    ContentView()
}

// 添加 String 扩展
extension String {
    func indented(by spaces: Int) -> String {
        let indent = String(repeating: " ", count: spaces)
        return self.components(separatedBy: .newlines)
            .map { $0.isEmpty ? $0 : indent + $0 }
            .joined(separator: "\n")
    }
}
