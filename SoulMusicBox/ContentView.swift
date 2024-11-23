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
                    ElementCheckRow(result: result)
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
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(logs) { log in
                        LogEntryView(log: log)
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
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(result.elementPath)
                Spacer()
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
    
    private let finder = UIElementFinder.shared
    private let logger = Logger.shared
    
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
                    .textSelection(.enabled)  // 允许用户选择和复制路径
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
