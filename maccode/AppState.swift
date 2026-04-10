import AppKit
import Combine
import Foundation
import Observation
import ClaudeCodeSDK

// MARK: - 应用全局状态

@Observable
@MainActor
class AppState {

    // MARK: 会话列表
    var sessions: [AgentSession] = []
    var selectedSessionId: UUID?

    // MARK: 消息（按会话 ID 存储）
    var messagesBySession: [UUID: [ChatMessage]] = [:]

    // MARK: 状态
    var isLoading: Bool = false
    var statusText: String = ""
    var errorMessage: String?
    var isClaudeInstalled: Bool = true

    // MARK: 设置
    let settings = AppSettings.shared

    // MARK: 私有
    private var client: ClaudeCodeClient?
    private var streamTask: Task<Void, Never>?

    // MARK: 计算属性

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
    }

    func initializeClient() {
        do {
            var config = ClaudeCodeConfiguration.default
            config.enableDebugLogging = false
            client = try ClaudeCodeClient(configuration: config)
            isClaudeInstalled = true
        } catch let error as ClaudeCodeError {
            if error.isInstallationError {
                isClaudeInstalled = false
                errorMessage = "未找到 claude 命令。\n请先安装：npm install -g @anthropic/claude-code"
            }
        } catch {
            errorMessage = "客户端初始化失败：\(error.localizedDescription)"
        }
    }

    // MARK: 会话管理

    func newSession(workingDir: String? = nil) {
        let dir = workingDir ?? settings.effectiveWorkingDirectory
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
    }

    func selectSession(_ session: AgentSession) {
        selectedSessionId = session.id
        errorMessage = nil
    }

    func deleteSession(_ session: AgentSession) {
        sessions.removeAll { $0.id == session.id }
        messagesBySession.removeValue(forKey: session.id)
        if selectedSessionId == session.id {
            selectedSessionId = sessions.first?.id
        }
    }

    // MARK: 加载已有会话（从 Claude 本地存储）

    func loadExistingSessions() {
        Task {
            do {
                let storage = ClaudeNativeSessionStorage()
                let stored = try await storage.getAllSessions()

                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "zh_CN")
                dateFormatter.doesRelativeDateFormatting = true
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .none

                var loaded: [AgentSession] = []
                for s in stored.sorted(by: { $0.lastAccessedAt > $1.lastAccessedAt }).prefix(100) {
                    let title: String
                    if let summary = s.summary, !summary.isEmpty {
                        title = String(summary.prefix(60))
                    } else {
                        title = "会话 \(s.id.prefix(8))"
                    }
                    let subtitle = URL(fileURLWithPath: s.projectPath).lastPathComponent
                    let timestamp = dateFormatter.string(from: s.lastAccessedAt)

                    var session = AgentSession(
                        title: title,
                        subtitle: subtitle,
                        timestamp: timestamp,
                        workingDirectory: s.projectPath
                    )
                    session.sdkSessionId = s.id

                    loaded.append(session)
                    // 加载消息摘要（取最后几条）
                    let recentMsgs = s.messages.suffix(20)
                    messagesBySession[session.id] = recentMsgs.map { msg in
                        let role: MessageRole = msg.role == .user ? .user : .assistant
                        return ChatMessage(role: role, blocks: [.text(msg.content)])
                    }
                }

                if !loaded.isEmpty {
                    sessions = loaded
                    selectedSessionId = loaded.first?.id
                }
            } catch {
                // 静默失败，以空会话列表开始
            }
        }
    }

    // MARK: 发送消息

    func sendMessage(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 如果没有会话则新建
        if selectedSession == nil {
            newSession()
        }
        guard let session = selectedSession else { return }

        // 取消正在进行的流
        streamTask?.cancel()

        // 添加用户消息
        appendMessage(ChatMessage(role: .user, blocks: [.text(trimmed)]), to: session.id)

        isLoading = true
        errorMessage = nil
        statusText = "正在连接..."

        let sessionId = session.id
        let sdkSessionId = session.sdkSessionId
        let workingDir = session.workingDirectory ?? settings.effectiveWorkingDirectory

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
            return
        }

        // 更新工作目录配置
        var config = client.configuration
        config.workingDirectory = workingDir
        if let apiKey = settings.anthropicApiKey.nilIfEmpty {
            config.environment["ANTHROPIC_API_KEY"] = apiKey
        }
        client.configuration = config

        // 构建选项
        var options = ClaudeCodeOptions()
        options.model = settings.selectedModel
        options.maxTurns = settings.maxTurns

        // 创建助手消息占位
        let assistantMsgId = UUID()
        appendMessage(ChatMessage(id: assistantMsgId, role: .assistant, blocks: [.text("")]), to: sessionId)

        do {
            let result: ClaudeCodeResult
            if let sid = sdkSessionId {
                result = try await client.resumeConversation(
                    sessionId: sid,
                    prompt: prompt,
                    outputFormat: .streamJson,
                    options: options
                )
            } else {
                result = try await client.runSinglePrompt(
                    prompt: prompt,
                    outputFormat: .streamJson,
                    options: options
                )
            }

            if case .stream(let publisher) = result {
                let mainPub = publisher.receive(on: DispatchQueue.main)
                do {
                    for try await chunk in mainPub.values {
                        if Task.isCancelled { break }
                        processChunk(chunk, sessionId: sessionId, assistantMsgId: assistantMsgId)
                    }
                } catch {
                    if !Task.isCancelled {
                        errorMessage = "流式响应中断：\(error.localizedDescription)"
                    }
                }
            } else if case .text(let text) = result {
                updateAssistantMessage(assistantMsgId, in: sessionId, text: text)
            } else if case .json(let msg) = result {
                updateAssistantMessage(assistantMsgId, in: sessionId, text: msg.result ?? "（操作完成，无文本输出）")
            }

        } catch let error as ClaudeCodeError {
            removeMessage(assistantMsgId, from: sessionId)
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
            statusText = "已连接 · \(msg.tools.count) 个工具可用"
            // 更新会话的 SDK 会话 ID（用于后续恢复）
            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[idx].sdkSessionId = msg.sessionId
            }

        case .assistant:
            statusText = "助手正在回复..."

        case .user:
            statusText = "工具执行中..."

        case .result(let msg):
            let text = msg.result ?? "（操作完成）"
            updateAssistantMessage(assistantMsgId, in: sessionId, text: text)
            // 更新会话副标题（显示费用）
            if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
                let cost = String(format: "%.4f", msg.totalCostUsd)
                let turns = msg.numTurns
                sessions[idx].subtitle = "费用 $\(cost) · \(turns) 轮对话"
                sessions[idx].timestamp = "刚刚"
            }
            statusText = ""
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
        statusText = ""
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
            // 同步更新当前会话的工作目录
            if let idx = sessions.firstIndex(where: { $0.id == selectedSessionId }) {
                sessions[idx].workingDirectory = url.path
                sessions[idx].subtitle = url.lastPathComponent
            }
        }
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

// MARK: - 辅助扩展

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
