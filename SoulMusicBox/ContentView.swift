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
    }
}

// 状态区域
struct StatusSection: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        GroupBox("应用状态") {
            VStack(alignment: .leading) {
                StatusRow(title: "QQ音乐", isRunning: viewModel.isQQMusicRunning)
                StatusRow(title: "Soul", isRunning: viewModel.isSoulRunning)
                StatusRow(title: "无障碍权限", isEnabled: viewModel.isAccessibilityEnabled)
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
    
    private let finder = UIElementFinder.shared
    private let logger = Logger.shared
    
    init() {
        setupLoggerCallback()
        checkApplicationStatus()
    }
    
    private func setupLoggerCallback() {
        logger.logCallback = { [weak self] level, message in
            DispatchQueue.main.async {
                self?.logs.append(LogEntry(level: level, message: message))
            }
        }
    }
    
    func checkApplicationStatus() {
        isAccessibilityEnabled = AXIsProcessTrustedWithOptions(nil)
        
        isQQMusicRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.tencent.QQMusicMac"
        }
        
        isSoulRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.soul.macapp"
        }
    }
    
    func checkAllElements() {
        do {
            try finder.loadConfig(from: "ui_config")
            
            // 检查 QQ音乐的控件
            if isQQMusicRunning {
                try checkQQMusicElements()
            }
            
            // 检查 Soul的控件
            if isSoulRunning {
                try checkSoulElements()
            }
            
        } catch {
            logger.error("加载配置文件失败: \(error)")
        }
    }
    
    private func checkQQMusicElements() throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.tencent.QQMusicMac" }) else {
            logger.error("QQ音乐未运行")
            return
        }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        try checkElement(named: "searchBox", in: "QQMusic", parent: appRef)
        try checkElement(named: "searchResults", in: "QQMusic", parent: appRef)
    }
    
    private func checkSoulElements() throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.soul.macapp" }) else {
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

#Preview {
    ContentView()
}
