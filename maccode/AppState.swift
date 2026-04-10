import AppKit
import Combine
import Foundation
import OSLog
import Observation
import ClaudeCodeSDK

// MARK: - 调试日志

let log = Logger(subsystem: "com.nl.maccode", category: "AppState")

// MARK: - 消息内容清洗

private func cleanContent(_ raw: String) -> String {
    var s = raw

    // 移除 <local-command-caveat>...</local-command-caveat> 块
    while let r = s.range(of: "<local-command-caveat>", options: .caseInsensitive),
          let e = s.range(of: "</local-command-caveat>", options: .caseInsensitive),
          r.lowerBound <= e.lowerBound {
        s.removeSubrange(r.lowerBound..<e.upperBound)
    }

    // 移除其他 XML/命令标签块（<command-name>, <command-message> 等）
    let tagPatterns = [
        "<command-name>", "</command-name>",
        "<command-message>", "</command-message>",
        "<command-args>", "</command-args>",
        "<local-command-caveat>", "</local-command-caveat>",
    ]
    for tag in tagPatterns {
        s = s.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
    }

    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 判断消息内容是否为系统/无效消息，应被过滤掉
private func isSystemMessage(_ content: String) -> Bool {
    let lower = content.lowercased()
    let systemPrefixes = [
        "<local-command-caveat>",
        "<command-name>",
        "caveat: the messages below",
        "do not respond to these messages",
    ]
    for prefix in systemPrefixes {
        if lower.contains(prefix) { return true }
    }
    // 纯 XML 标签行
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") { return true }
    return false
}

// MARK: - 应用全局状态

@Observable
@MainActor
class AppState {

    // MARK: 项目列表
    var projects: [Project] = []
    var selectedProjectId: UUID?

    // MARK: 会话列表（全部）
    var sessions: [AgentSession] = []
    var selectedSessionId: UUID?

    // MARK: 消息（按会话 ID 存储）
    var messagesBySession: [UUID: [ChatMessage]] = [:]

    // MARK: 状态
    var isLoading: Bool = false
    var statusText: String = ""
    var errorMessage: String?
    var isClaudeInstalled: Bool = true

    // MARK: 调试日志（最新 200 条）
    var debugLogs: [DebugLogEntry] = []

    // MARK: 设置
    let settings = AppSettings.shared

    // MARK: 私有
    private var client: ClaudeCodeClient?
    private var streamTask: Task<Void, Never>?

    // MARK: 计算属性

    /// 当前选中项目
    var selectedProject: Project? {
        projects.first { $0.id == selectedProjectId }
    }

    /// 当前项目下的会话（按最近时间排序）
    var currentProjectSessions: [AgentSession] {
        guard let proj = selectedProject else {
            // 未选项目：显示无目录的会话
            return sessions.filter { $0.workingDirectory == nil }
        }
        return sessions.filter { $0.workingDirectory == proj.path }
    }

    var selectedSession: AgentSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    var currentMessages: [ChatMessage] {
        guard let id = selectedSessionId else { return [] }
        return messagesBySession[id] ?? []
    }

    // MARK: 初始化

    init() {
        initializeClient()
        loadSavedProjects()
    }

    func initializeClient() {
        do {
            var config = ClaudeCodeConfiguration.default
            config.enableDebugLogging = false
            client = try ClaudeCodeClient(configuration: config)
            isClaudeInstalled = true
            addLog(.info, "ClaudeCodeClient 初始化成功")
        } catch let error as ClaudeCodeError {
            if error.isInstallationError {
                isClaudeInstalled = false
                errorMessage = "未找到 claude 命令。\n请先安装：npm install -g @anthropic/claude-code"
                addLog(.error, "claude 未安装：\(error)")
            }
        } catch {
            errorMessage = "客户端初始化失败：\(error.localizedDescription)"
            addLog(.error, "初始化失败：\(error)")
        }
    }

    // MARK: 项目管理

    /// 打开目录选择器添加新项目
    func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "添加项目"
        panel.message = "选择项目根目录"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // 若已存在同路径项目，直接切换
        if let existing = projects.first(where: { $0.path == url.path }) {
            selectedProjectId = existing.id
            selectedSessionId = currentProjectSessions.first?.id
            addLog(.info, "切换到已有项目：\(url.path)")
            return
        }

        let proj = Project(name: url.lastPathComponent, path: url.path)
        projects.insert(proj, at: 0)
        selectedProjectId = proj.id
        selectedSessionId = nil
        saveProjects()
        addLog(.info, "添加项目：\(url.path)")
    }

    /// 删除项目（不删除会话数据）
    func removeProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selectedProjectId == project.id {
            selectedProjectId = projects.first?.id
            selectedSessionId = currentProjectSessions.first?.id
        }
        saveProjects()
        addLog(.info, "移除项目：\(project.path)")
    }

    /// 选中项目
    func selectProject(_ project: Project) {
        selectedProjectId = project.id
        // 自动选中该项目最近的会话
        selectedSessionId = currentProjectSessions.first?.id
        errorMessage = nil
        addLog(.info, "切换项目：\(project.name)")
    }

    /// 持久化项目列表
    private func saveProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: "savedProjects")
        }
    }

    private func loadSavedProjects() {
        guard let data = UserDefaults.standard.data(forKey: "savedProjects"),
              let saved = try? JSONDecoder().decode([Project].self, from: data) else { return }
        projects = saved
        selectedProjectId = projects.first?.id
        addLog(.info, "从本地加载 \(projects.count) 个项目")
    }

    // MARK: 会话管理

    func newSession(workingDir: String? = nil) {
        // 优先用当前选中项目的路径
        let dir = workingDir ?? selectedProject?.path ?? settings.effectiveWorkingDirectory
        let session = AgentSession(
            title: "新对话",
            subtitle: dir.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "未选择目录",
            timestamp: "刚刚",
            workingDirectory: dir
        )
        sessions.insert(session, at: 0)
        selectedSessionId = session.id
        messagesBySession[session.id] = []
        errorMessage = nil

        // 若当前没有项目且有目录，自动创建项目
        if let dir, selectedProject?.path != dir {
            if !projects.contains(where: { $0.path == dir }) {
                let proj = Project(name: URL(fileURLWithPath: dir).lastPathComponent, path: dir)
                projects.insert(proj, at: 0)
                selectedProjectId = proj.id
                saveProjects()
            }
        }
        addLog(.info, "新建会话，目录=\(dir ?? "无")")
    }

    func selectSession(_ session: AgentSession) {
        selectedSessionId = session.id
        errorMessage = nil
        addLog(.info, "切换会话 \(session.sdkSessionId ?? session.id.uuidString)")
    }

    func deleteSession(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        messagesBySession.removeValue(forKey: session.id)
        if selectedSessionId == session.id {
            selectedSessionId = sessions.first?.id
        }
        addLog(.info, "删除会话 \(session.id)")
    }

    // MARK: 加载已有会话（从 Claude 本地存储）

    func loadExistingSessions() {
        Task {
            addLog(.info, "开始加载历史会话...")
            do {
                let storage = ClaudeNativeSessionStorage()
                let stored = try await storage.getAllSessions()
                addLog(.info, "共找到 \(stored.count) 个历史会话")

                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "zh_CN")
                dateFormatter.doesRelativeDateFormatting = true
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .none

                var loaded: [AgentSession] = []
                for s in stored.sorted(by: { $0.lastAccessedAt > $1.lastAccessedAt }).prefix(100) {

                    // 过滤有效消息（去除系统消息）
                    let validMessages = s.messages.filter { msg in
                        !isSystemMessage(msg.content) && !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }

                    // 如果会话完全没有有效消息，跳过
                    if validMessages.isEmpty && s.summary == nil {
                        addLog(.debug, "跳过空会话 \(s.id.prefix(8))")
                        continue
                    }

                    // 生成会话标题
                    let title: String
                    if let summary = s.summary, !summary.isEmpty {
                        title = String(summary.prefix(60))
                    } else if let firstUserMsg = validMessages.first(where: { $0.role == .user }) {
                        let cleaned = cleanContent(firstUserMsg.content)
                        title = String(cleaned.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                    } else {
                        title = "会话 \(s.id.prefix(8))"
                    }

                    let subtitle = URL(fileURLWithPath: s.projectPath).lastPathComponent
                    let timestamp = dateFormatter.string(from: s.lastAccessedAt)

                    var session = AgentSession(
                        title: title.isEmpty ? "会话 \(s.id.prefix(8))" : title,
                        subtitle: subtitle,
                        timestamp: timestamp,
                        workingDirectory: s.projectPath
                    )
                    session.sdkSessionId = s.id

                    loaded.append(session)

                    // 加载并清洗最近消息
                    let recentMsgs = validMessages.suffix(30)
                    messagesBySession[session.id] = recentMsgs.compactMap { msg in
                        let cleaned = cleanContent(msg.content)
                        guard !cleaned.isEmpty else { return nil }
                        let role: MessageRole = msg.role == .user ? .user : .assistant
                        return ChatMessage(role: role, blocks: [.text(cleaned)])
                    }
                }

                if !loaded.isEmpty {
                    sessions = loaded

                    // 从历史会话中自动发现项目（去重）
                    var discoveredPaths = Set<String>()
                    var newProjects: [Project] = []
                    for session in loaded {
                        guard let path = session.workingDirectory,
                              !path.isEmpty,
                              !discoveredPaths.contains(path),
                              !projects.contains(where: { $0.path == path }) else { continue }
                        discoveredPaths.insert(path)
                        newProjects.append(Project(
                            name: URL(fileURLWithPath: path).lastPathComponent,
                            path: path
                        ))
                    }
                    if !newProjects.isEmpty {
                        projects.append(contentsOf: newProjects)
                        saveProjects()
                        addLog(.info, "自动发现 \(newProjects.count) 个新项目")
                    }

                    // 若没有已选项目，默认选第一个
                    if selectedProjectId == nil {
                        selectedProjectId = projects.first?.id
                    }
                    selectedSessionId = currentProjectSessions.first?.id
                    addLog(.info, "成功加载 \(loaded.count) 个会话，\(projects.count) 个项目")
                } else {
                    addLog(.info, "未找到有效历史会话")
                }
            } catch {
                addLog(.error, "加载历史会话失败：\(error)")
            }
        }
    }

    // MARK: 发送消息

    func sendMessage(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if selectedSession == nil {
            newSession()
        }
        guard let session = selectedSession else { return }

        streamTask?.cancel()

        appendMessage(ChatMessage(role: .user, blocks: [.text(trimmed)]), to: session.id)

        isLoading = true
        errorMessage = nil
        statusText = "正在连接..."

        let sessionId = session.id
        let sdkSessionId = session.sdkSessionId
        let workingDir = session.workingDirectory ?? settings.effectiveWorkingDirectory

        addLog(.info, "发送消息，会话=\(sdkSessionId ?? "新建")，目录=\(workingDir ?? "无")")

        streamTask = Task {
            await doSend(
                prompt: trimmed,
                sessionId: sessionId,
                sdkSessionId: sdkSessionId,
                workingDir: workingDir
            )
        }
    }

    private func doSend(prompt: String, sessionId: UUID, sdkSessionId: String?, workingDir: String?) async {
        guard let client = client else {
            errorMessage = "Claude Code 客户端未初始化，请检查 claude 是否已安装"
            isLoading = false
            statusText = ""
            addLog(.error, "客户端未初始化")
            return
        }

        var config = client.configuration
        config.workingDirectory = workingDir
        if let apiKey = settings.anthropicApiKey.nilIfEmpty {
            config.environment["ANTHROPIC_API_KEY"] = apiKey
        }
        client.configuration = config

        var options = ClaudeCodeOptions()
        options.model = settings.selectedModel
        options.maxTurns = settings.maxTurns

        let assistantMsgId = UUID()
        appendMessage(ChatMessage(id: assistantMsgId, role: .assistant, blocks: [.text("")]), to: sessionId)

        do {
            // 使用 .json 格式：等待完整结果，result.result 有值
            // streamJson 格式下 result.result = null，内容在 .assistant chunk 里需要 SwiftAnthropic
            let result: ClaudeCodeResult
            if let sid = sdkSessionId {
                addLog(.info, "恢复会话 \(sid.prefix(8))...")
                result = try await client.resumeConversation(
                    sessionId: sid,
                    prompt: prompt,
                    outputFormat: .json,
                    options: options
                )
            } else {
                addLog(.info, "新建对话，模型=\(settings.selectedModel)")
                result = try await client.runSinglePrompt(
                    prompt: prompt,
                    outputFormat: .json,
                    options: options
                )
            }

            addLog(.debug, "收到结果类型：\(resultTypeName(result))")

            switch result {
            case .json(let msg):
                let text = msg.result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty {
                    // json 格式理论上有 result，若仍为空则退一步用 streamJson 重试
                    addLog(.error, "json result 为空，isError=\(msg.isError)，subtype=\(msg.subtype)")
                    updateAssistantMessage(assistantMsgId, in: sessionId,
                                          text: "⚠️ 收到空响应（isError=\(msg.isError)，subtype=\(msg.subtype)）\n请打开调试日志查看详情。")
                } else {
                    updateAssistantMessage(assistantMsgId, in: sessionId, text: text)
                }
                // 更新会话信息
                let sdkId = msg.sessionId
                let cost = String(format: "%.4f", msg.totalCostUsd)
                if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                    sessions[idx].sdkSessionId = sdkId
                    sessions[idx].subtitle = "费用 $\(cost) · \(msg.numTurns) 轮"
                    sessions[idx].timestamp = "刚刚"
                }
                addLog(.info, "完成：费用=$\(msg.totalCostUsd)，轮数=\(msg.numTurns)，耗时=\(msg.durationMs)ms，sessionId=\(sdkId.prefix(8))")

            case .text(let text):
                updateAssistantMessage(assistantMsgId, in: sessionId, text: text)
                addLog(.info, "收到 text 响应，长度=\(text.count)")

            case .stream(let publisher):
                // 若 SDK 降级返回 stream，从 result chunk 取最终文本
                addLog(.info, "收到 stream，等待 result chunk...")
                var finalText: String? = nil
                var capturedSessionId: String? = nil
                let mainPub = publisher.receive(on: DispatchQueue.main)
                do {
                    for try await chunk in mainPub.values {
                        if Task.isCancelled { break }
                        switch chunk {
                        case .initSystem(let m):
                            capturedSessionId = m.sessionId
                            statusText = "已连接 · \(m.tools.count) 个工具"
                            addLog(.info, "stream initSystem sessionId=\(m.sessionId.prefix(8))")
                        case .result(let m):
                            finalText = m.result
                            let cost = String(format: "%.4f", m.totalCostUsd)
                            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                                sessions[idx].sdkSessionId = capturedSessionId ?? m.sessionId
                                sessions[idx].subtitle = "费用 $\(cost) · \(m.numTurns) 轮"
                                sessions[idx].timestamp = "刚刚"
                            }
                            addLog(.info, "stream result：费用=$\(m.totalCostUsd)，result=\(m.result?.prefix(50) ?? "nil")")
                        case .assistant:
                            statusText = "助手正在回复..."
                        case .user:
                            statusText = "工具执行中..."
                        }
                    }
                } catch {
                    addLog(.error, "stream 中断：\(error)")
                }
                updateAssistantMessage(assistantMsgId, in: sessionId,
                                       text: finalText ?? "（响应完成，无文本输出）")
            }

        } catch let error as ClaudeCodeError {
            removeMessage(assistantMsgId, from: sessionId)
            addLog(.error, "ClaudeCodeError：\(error)")
            switch error {
            case .notInstalled:
                errorMessage = "未找到 claude 命令\n请运行：npm install -g @anthropic/claude-code"
                isClaudeInstalled = false
            case .rateLimitExceeded:
                errorMessage = "API 请求频率受限，请稍后重试"
            case .timeout:
                errorMessage = "请求超时，请重试"
            case .cancelled:
                break
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            removeMessage(assistantMsgId, from: sessionId)
            if !Task.isCancelled {
                addLog(.error, "未知错误：\(error)")
                errorMessage = "请求失败：\(error.localizedDescription)"
            }
        }

        isLoading = false
        statusText = ""
        streamTask = nil
    }

    private func processChunk(_ chunk: ResponseChunk, sessionId: UUID, assistantMsgId: UUID) {
        switch chunk {
        case .initSystem(let msg):
            statusText = "已连接 · \(msg.tools.count) 个工具"
            addLog(.info, "已连接，SDK 会话 ID=\(msg.sessionId.prefix(8))，工具=\(msg.tools.joined(separator: ","))")
            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[idx].sdkSessionId = msg.sessionId
            }

        case .assistant:
            statusText = "助手正在回复..."
            addLog(.debug, "收到 assistant chunk")

        case .user:
            statusText = "工具执行中..."
            addLog(.debug, "收到 user chunk（工具结果）")

        case .result(let msg):
            let text = msg.result ?? "（操作完成）"
            updateAssistantMessage(assistantMsgId, in: sessionId, text: text)
            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                let cost = String(format: "%.4f", msg.totalCostUsd)
                sessions[idx].subtitle = "费用 $\(cost) · \(msg.numTurns) 轮"
                sessions[idx].timestamp = "刚刚"
            }
            addLog(.info, "响应完成，费用=$\(msg.totalCostUsd)，轮数=\(msg.numTurns)，耗时=\(msg.durationMs)ms")
            statusText = ""
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
        statusText = ""
        addLog(.info, "用户取消响应")
    }

    // MARK: 选择工作目录

    func selectWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择目录"
        panel.message = "选择 Claude Code 的工作目录（通常是项目根目录）"

        if panel.runModal() == .OK, let url = panel.url {
            settings.workingDirectory = url.path
            addLog(.info, "设置工作目录：\(url.path)")
            if let idx = sessions.firstIndex(where: { $0.id == selectedSessionId }) {
                sessions[idx].workingDirectory = url.path
                sessions[idx].subtitle = url.lastPathComponent
            }
        }
    }

    // MARK: 调试日志

    func addLog(_ level: DebugLogEntry.Level, _ message: String) {
        let entry = DebugLogEntry(level: level, message: message)
        debugLogs.append(entry)
        if debugLogs.count > 200 { debugLogs.removeFirst() }
        // 同步到 OSLog
        switch level {
        case .debug: log.debug("\(message)")
        case .info:  log.info("\(message)")
        case .error: log.error("\(message)")
        }
    }

    func clearLogs() {
        debugLogs.removeAll()
    }

    // MARK: 私有工具方法

    private func appendMessage(_ message: ChatMessage, to sessionId: UUID) {
        if messagesBySession[sessionId] == nil {
            messagesBySession[sessionId] = []
        }
        messagesBySession[sessionId]?.append(message)
    }

    private func updateAssistantMessage(_ id: UUID, in sessionId: UUID, text: String) {
        guard let idx = messagesBySession[sessionId]?.firstIndex(where: { $0.id == id }) else { return }
        messagesBySession[sessionId]?[idx].blocks = [.text(text)]
    }

    private func removeMessage(_ id: UUID, from sessionId: UUID) {
        messagesBySession[sessionId]?.removeAll { $0.id == id }
    }
}

// MARK: - 调试日志条目

struct DebugLogEntry: Identifiable {
    enum Level { case debug, info, error }
    let id = UUID()
    let level: Level
    let message: String
    let time = Date()

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: time)
    }

    var color: String {
        switch level {
        case .debug: return "secondary"
        case .info:  return "primary"
        case .error: return "red"
        }
    }
}

// MARK: - 辅助函数

private func resultTypeName(_ result: ClaudeCodeResult) -> String {
    switch result {
    case .text:   return "text"
    case .json:   return "json"
    case .stream: return "stream"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
