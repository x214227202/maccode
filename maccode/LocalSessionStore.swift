import Foundation

// MARK: - 本地会话缓存存储
//
// 解决的问题：
// 1. 每次从 Claude 原生 JSONL 读取慢，UUID 不稳定
// 2. 切换会话后中间区域空白（UUID 失效）
// 3. 应用重启后需重新解析，体验差
//
// 存储位置：~/Library/Application Support/com.nl.maccode/sessions/{uuid}.json

// MARK: - 可序列化模型

struct LocalSession: Codable {
    var id: UUID
    var sdkSessionId: String?
    var title: String
    var subtitle: String
    var timestamp: TimeInterval      // Date.timeIntervalSince1970
    var workingDirectory: String?
    var messages: [LocalMessage]
    var lastUpdated: TimeInterval

    init(from session: AgentSession, messages: [ChatMessage]) {
        self.id = session.id
        self.sdkSessionId = session.sdkSessionId
        self.title = session.title
        self.subtitle = session.subtitle
        self.timestamp = Date().timeIntervalSince1970
        self.workingDirectory = session.workingDirectory
        self.messages = messages.map { LocalMessage(from: $0) }
        self.lastUpdated = Date().timeIntervalSince1970
    }

    func toAgentSession() -> AgentSession {
        var s = AgentSession(
            title: title,
            subtitle: subtitle,
            timestamp: relativeTimestamp(),
            workingDirectory: workingDirectory
        )
        s.id = id
        s.sdkSessionId = sdkSessionId
        return s
    }

    func toChatMessages() -> [ChatMessage] {
        messages.compactMap { $0.toChatMessage() }
    }

    private func relativeTimestamp() -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct LocalMessage: Codable {
    var id: UUID
    var role: String          // "user" | "assistant" | "tool"
    var blocks: [LocalBlock]

    init(from msg: ChatMessage) {
        self.id = msg.id
        self.role = msg.role == .user ? "user" : msg.role == .assistant ? "assistant" : "tool"
        self.blocks = msg.blocks.map { LocalBlock(from: $0) }
    }

    func toChatMessage() -> ChatMessage? {
        let role: MessageRole
        switch self.role {
        case "user":      role = .user
        case "assistant": role = .assistant
        case "tool":      role = .tool
        default: return nil
        }
        let messageBlocks = blocks.compactMap { $0.toMessageBlock() }
        return ChatMessage(id: id, role: role, blocks: messageBlocks)
    }
}

struct LocalBlock: Codable {
    var type: String          // "text" | "thinking" | "toolCall"
    // text / thinking
    var content: String?
    // toolCall
    var blockId: UUID?
    var toolId: String?
    var toolName: String?
    var args: String?
    var result: String?

    init(from block: MessageBlock) {
        switch block {
        case .text(let s):
            self.type = "text"; self.content = s
        case .thinking(let s):
            self.type = "thinking"; self.content = s
        case .toolCall(let tc):
            self.type = "toolCall"
            self.blockId = tc.id
            self.toolId = tc.toolId
            self.toolName = tc.toolName
            self.args = tc.args
            self.result = tc.result
        }
    }

    func toMessageBlock() -> MessageBlock? {
        switch type {
        case "text":
            return .text(content ?? "")
        case "thinking":
            return .thinking(content ?? "")
        case "toolCall":
            guard let name = toolName else { return nil }
            var tc = ToolCallBlock(toolName: name, args: args ?? "", result: result, toolId: toolId)
            if let bid = blockId { tc.id = bid }
            return .toolCall(tc)
        default:
            return nil
        }
    }
}

// MARK: - 存储器

final class LocalSessionStore {

    static let shared = LocalSessionStore()

    private let dir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = appSupport.appendingPathComponent("com.nl.maccode/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func url(for id: UUID) -> URL {
        dir.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: 读

    /// 加载所有缓存会话（同步，启动时立即可用）
    func loadAll() -> [(AgentSession, [ChatMessage])] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        var result: [(LocalSession)] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let local = try? decoder.decode(LocalSession.self, from: data) else { continue }
            result.append(local)
        }

        // 按最后更新时间倒序
        result.sort { $0.lastUpdated > $1.lastUpdated }
        return result.map { ($0.toAgentSession(), $0.toChatMessages()) }
    }

    /// 查单个会话的消息（延迟加载）
    func loadMessages(for id: UUID) -> [ChatMessage]? {
        guard let data = try? Data(contentsOf: url(for: id)),
              let local = try? JSONDecoder().decode(LocalSession.self, from: data) else { return nil }
        return local.toChatMessages()
    }

    // MARK: 写（在调用方主线程编码为 Data，仅文件写入放后台）

    /// 保存/更新单个会话
    func save(_ session: AgentSession, messages: [ChatMessage]) {
        let local = LocalSession(from: session, messages: messages)
        // 编码在调用线程（主线程），JSON 序列化速度极快
        guard let data = try? JSONEncoder().encode(local) else { return }
        writeAsync(data: data, to: url(for: session.id))
    }

    /// 只更新标题/字幕等元数据，不覆盖消息
    /// decode/encode 在调用线程（主线程）完成，文件写入放后台
    func updateMeta(_ session: AgentSession) {
        let fileURL = url(for: session.id)
        guard let existing = try? Data(contentsOf: fileURL),
              var local = try? JSONDecoder().decode(LocalSession.self, from: existing) else { return }
        local.title = session.title
        local.subtitle = session.subtitle
        if let sid = session.sdkSessionId { local.sdkSessionId = sid }
        local.lastUpdated = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(local) else { return }
        writeAsync(data: data, to: fileURL)
    }

    private func writeAsync(data: Data, to file: URL) {
        Task.detached(priority: .utility) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// 删除缓存
    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// 检查是否已有本地缓存
    func exists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    /// 检查是否已有指定 sdkSessionId 的本地缓存
    func existsBySdkId(_ sdkId: String) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return false }
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let local = try? decoder.decode(LocalSession.self, from: data),
                  local.sdkSessionId == sdkId else { continue }
            return true
        }
        return false
    }
}
