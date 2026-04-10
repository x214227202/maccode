import AppKit
import Combine
import SwiftUI

// MARK: - 数据模型

struct AgentSession: Identifiable {
    var id = UUID()
    var title: String
    var subtitle: String
    var timestamp: String
    var isActive: Bool = false
    var sdkSessionId: String?       // Claude SDK 会话 ID（用于恢复对话）
    var workingDirectory: String?   // 工作目录
}

enum MessageRole { case user, assistant }

struct ToolCallBlock: Identifiable {
    var id = UUID()
    var toolName: String
    var args: String
    var result: String?
    var toolId: String?
}

enum MessageBlock {
    case text(String)
    case toolCall(ToolCallBlock)
}

struct ChatMessage: Identifiable {
    var id: UUID
    var role: MessageRole
    var blocks: [MessageBlock]

    init(id: UUID = UUID(), role: MessageRole, blocks: [MessageBlock] = []) {
        self.id = id
        self.role = role
        self.blocks = blocks
    }
}

// MARK: - 项目模型

struct Project: Identifiable, Codable {
    var id: UUID
    var name: String     // 显示名称（一般是目录名）
    var path: String     // 完整路径
    var lastUsed: Date

    init(name: String, path: String) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.lastUsed = Date()
    }
}

// MARK: - 文件树

struct FileNode: Identifiable {
    let id = UUID()
    var name: String
    var isDir: Bool
    var depth: Int
    var isModified: Bool = false
}

// MARK: - 主视图

struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showFiles = true
    @State private var showDebugLog = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(showDebugLog: $showDebugLog)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            ChatView(showFiles: $showFiles)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            appState.loadExistingSessions()
        }
        .sheet(isPresented: $showDebugLog) {
            DebugLogView()
                .environment(appState)
        }
    }
}

// MARK: - 侧边栏

enum SidebarTab { case projects, sessions }

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Binding var showDebugLog: Bool
    @State private var activeTab: SidebarTab = .projects
    @State private var search = ""
    @State private var showSettings = false
    @State private var refreshRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // 红绿灯留白
            Spacer().frame(height: 36)

            // ── 胶囊切换按钮 ─────────────────────────
            SidebarTabPicker(activeTab: $activeTab)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            // ── 搜索框 ───────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.45))
                TextField(activeTab == .projects ? "搜索项目..." : "搜索对话内容...", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .cornerRadius(7)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.15)

            // ── 统一项目树 ───────────────────────────
            ProjectTreePanel(activeTab: activeTab, search: search)

            Divider().opacity(0.15)

            // ── 底部工具栏 ───────────────────────────
            HStack(spacing: 14) {
                Button(action: {
                    withAnimation(.linear(duration: 0.5)) { refreshRotation += 360 }
                    appState.loadExistingSessions()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(refreshRotation))
                }
                .buttonStyle(.plain).help("刷新历史会话")

                Spacer()

                Button(action: { showDebugLog = true }) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain).help("调试日志")

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

// MARK: - 胶囊切换组件

struct SidebarTabPicker: View {
    @Binding var activeTab: SidebarTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "项目", icon: "folder", tab: .projects)
            tabButton(title: "对话", icon: "message", tab: .sessions)
        }
        .padding(3)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }

    @ViewBuilder
    func tabButton(title: String, icon: String, tab: SidebarTab) -> some View {
        let isActive = activeTab == tab
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) { activeTab = tab }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            }
            .foregroundColor(isActive ? .white : .secondary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.white.opacity(0.14) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isActive ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 统一项目树（Accordion）

struct ProjectTreePanel: View {
    @Environment(AppState.self) var appState
    let activeTab: SidebarTab
    let search: String

    var displayedProjects: [Project] {
        if search.isEmpty { return appState.projects }
        if activeTab == .projects {
            return appState.projects.filter { $0.name.localizedCaseInsensitiveContains(search) }
        } else {
            return appState.projects.filter { proj in
                appState.sessions.filter { $0.workingDirectory == proj.path }
                    .contains { $0.title.localizedCaseInsensitiveContains(search) }
            }
        }
    }

    func sessionsFor(_ project: Project) -> [AgentSession] {
        let all = appState.sessions.filter { $0.workingDirectory == project.path }
        if search.isEmpty || activeTab == .projects { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        if displayedProjects.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: search.isEmpty ? "folder.badge.plus" : "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.2))
                Text(search.isEmpty ? "添加项目目录" : "无匹配结果")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.45))
                if search.isEmpty {
                    Button(action: { appState.addProject() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                            Text("添加项目").font(.system(size: 12))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(8)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedProjects) { project in
                        let isExpanded = appState.selectedProjectId == project.id
                        let projectSessions = sessionsFor(project)

                        // ── 项目行 ────────────────────────────
                        ProjectAccordionRow(
                            project: project,
                            isExpanded: isExpanded,
                            sessionCount: appState.sessions.filter { $0.workingDirectory == project.path }.count
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                if isExpanded {
                                    // 再次点击已展开项目 → 收起
                                    appState.selectedProjectId = nil
                                    appState.selectedSessionId = nil
                                } else {
                                    appState.selectProject(project)
                                }
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.removeProject(project)
                            } label: {
                                Label("移除项目", systemImage: "trash")
                            }
                        }

                        // ── 展开内容 ──────────────────────────
                        if isExpanded {
                            // 新建会话按钮
                            Button(action: { appState.newSession() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("新建会话")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color.blue.opacity(0.75))
                                .cornerRadius(8)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)

                            // 会话列表
                            ForEach(projectSessions) { session in
                                let isSelected = appState.selectedSessionId == session.id
                                let msgCount = appState.messagesBySession[session.id]?.count ?? 0
                                SessionAccordionRow(
                                    session: session,
                                    isSelected: isSelected,
                                    msgCount: msgCount
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { appState.selectSession(session) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        appState.deleteSession(session)
                                    } label: {
                                        Label("删除对话", systemImage: "trash")
                                    }
                                }
                            }

                            if projectSessions.isEmpty {
                                HStack {
                                    Text("暂无对话，点击新建")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.4))
                                        .padding(.horizontal, 16).padding(.vertical, 6)
                                    Spacer()
                                }
                            }
                        }

                        Divider().opacity(0.08).padding(.horizontal, 4)
                    }

                    // ── 底部添加项目 ──────────────────────────
                    Button(action: { appState.addProject() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("添加项目")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 项目 Accordion 行

struct ProjectAccordionRow: View {
    let project: Project
    let isExpanded: Bool
    let sessionCount: Int

    var body: some View {
        HStack(spacing: 10) {
            // 文件夹图标
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 14))
                .foregroundColor(isExpanded ? .white : .secondary.opacity(0.55))
                .frame(width: 18)

            // 文字区
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 12, weight: isExpanded ? .semibold : .medium))
                    .foregroundColor(isExpanded ? .white : .primary.opacity(0.82))
                    .lineLimit(1)
                Text(abbreviatePath(project.path))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            // 会话数徽标
            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isExpanded ? .white.opacity(0.7) : .secondary.opacity(0.4))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(isExpanded ? Color.white.opacity(0.15) : Color.white.opacity(0.07))
                    .cornerRadius(4)
            }

            // 展开箭头
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(isExpanded ? Color.blue.opacity(0.12) : Color.clear)
    }

    func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - 会话 Accordion 行

struct SessionAccordionRow: View {
    let session: AgentSession
    let isSelected: Bool
    let msgCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左侧选中指示条
            Rectangle()
                .fill(isSelected ? Color.blue.opacity(0.85) : Color.clear)
                .frame(width: 2)
                .padding(.vertical, 6)

            // Claude 风格图标
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: 0.95, green: 0.38, blue: 0.25).opacity(0.88))
                    .frame(width: 24, height: 24)
                Image(systemName: "asterisk")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 7)

            // 标题 + 时间行
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary.opacity(0.82))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.45))
                    Text(session.timestamp)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.45))
                }
            }
            .padding(.top, 6)

            Spacer()

            // 消息数
            if msgCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(msgCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.4))
                    Image(systemName: "bubble.left")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.top, 7)
            }

            // 活跃绿点
            if session.isActive {
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 6, height: 6)
                    .padding(.top, 12)
            }
        }
        .padding(.trailing, 10)
        .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
    }
}

// MARK: - 聊天视图

struct ChatView: View {
    @Environment(AppState.self) var appState
    @Binding var showFiles: Bool
    @State private var selectedModel = "claude-sonnet-4-6"

    private let models = [
        "claude-sonnet-4-6",
        "claude-opus-4-6",
        "claude-haiku-4-5",
    ]
    private let modelLabels = [
        "claude-sonnet-4-6": "Sonnet",
        "claude-opus-4-6": "Opus",
        "claude-haiku-4-5": "Haiku",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.selectedSession?.title ?? "未选择对话")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let sub = appState.selectedSession?.subtitle {
                        Text(sub)
                            .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()

                // 状态指示
                if appState.isLoading {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6)
                        if !appState.statusText.isEmpty {
                            Text(appState.statusText)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.trailing, 8)
                }

                // 模型选择
                Picker("", selection: $selectedModel) {
                    ForEach(models, id: \.self) { model in
                        Text(modelLabels[model] ?? model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.system(size: 12))
                .frame(width: 90)
                .onChange(of: selectedModel) { _, new in
                    appState.settings.selectedModel = new
                }
                .onAppear {
                    selectedModel = appState.settings.selectedModel
                }

                // 工作目录选择
                Button(action: { appState.selectWorkingDirectory() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text(appState.settings.workingDirectoryName)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button(action: { showFiles.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .foregroundColor(showFiles ? .primary.opacity(0.6) : .secondary.opacity(0.4))
                }.buttonStyle(.plain)

                Button(action: { appState.newSession() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            Divider().opacity(0.2)

            // 错误横幅
            if let err = appState.errorMessage {
                ErrorBanner(message: err) {
                    appState.errorMessage = nil
                }
            }

            // 消息列表
            if appState.selectedSession == nil {
                // 欢迎界面
                WelcomeView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(appState.currentMessages) { msg in
                                ChatMessageView(message: msg)
                                    .id(msg.id)
                            }
                            // 流式响应时的加载占位
                            if appState.isLoading && appState.currentMessages.last?.role == .user {
                                ThinkingIndicator()
                                    .id("thinking")
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: appState.currentMessages.count) { _, _ in
                        withAnimation {
                            if let lastId = appState.currentMessages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // 输入框
            AgentInputView()
                .padding(.horizontal, 80)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
        .inspector(isPresented: $showFiles) {
            FilesPanel(showFiles: $showFiles, session: appState.selectedSession)
                .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
        }
    }
}

// MARK: - 欢迎界面

struct WelcomeView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.38, blue: 0.25), Color(red: 0.85, green: 0.25, blue: 0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "asterisk").font(.system(size: 28, weight: .bold)).foregroundColor(.white))

            Text("Claude Code")
                .font(.system(size: 22, weight: .semibold))
            Text("macOS 本地客户端")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Button(action: { appState.newSession() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("新建对话")
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 错误横幅

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.3)), alignment: .bottom)
    }
}

// MARK: - 思考中指示器

struct ThinkingIndicator: View {
    @State private var dotPhase = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.38, blue: 0.25), Color(red: 0.85, green: 0.25, blue: 0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "asterisk").font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                .padding(.top, 2)

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary.opacity(i == dotPhase ? 0.7 : 0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 10)
            Spacer()
        }
        .padding(.bottom, 18)
        .onReceive(timer) { _ in
            dotPhase = (dotPhase + 1) % 3
        }
    }
}

// MARK: - 聊天消息视图

struct ChatMessageView: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var avatar: some View {
        Group {
            if isUser {
                Circle().fill(Color.indigo.opacity(0.85)).frame(width: 26, height: 26)
                    .overlay(Text("U").font(.system(size: 12, weight: .bold)).foregroundColor(.white))
            } else {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.95, green: 0.38, blue: 0.25), Color(red: 0.85, green: 0.25, blue: 0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "asterisk").font(.system(size: 14, weight: .bold)).foregroundColor(.white))
            }
        }
        .padding(.top, 2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let t):
                            if !t.isEmpty {
                                Text(t)
                                    .font(.system(size: 13))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.22))
                                    .cornerRadius(12)
                            }
                        case .toolCall(let tc):
                            ToolCallView(tool: tc)
                        }
                    }
                }
                avatar
            } else {
                avatar
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let t):
                            if !t.isEmpty {
                                MarkdownText(text: t)
                                    .font(.system(size: 13))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                            } else {
                                // 等待响应占位（动态省略号）
                                ThinkingIndicator()
                            }
                        case .toolCall(let tc):
                            ToolCallView(tool: tc)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 18)
    }
}

// MARK: - 工具调用视图

struct ToolCallView: View {
    let tool: ToolCallBlock
    @State private var expanded = false

    var icon: String {
        switch tool.toolName.lowercased() {
        case "grep":  return "magnifyingglass"
        case "read":  return "doc.text"
        case "edit", "write":  return "pencil.and.outline"
        case "bash", "shell": return "terminal"
        case "glob":  return "folder.badge.questionmark"
        default:      return "wrench.and.screwdriver"
        }
    }

    var accentColor: Color {
        switch tool.toolName.lowercased() {
        case "edit", "write":  return .orange
        case "bash", "shell":  return .green
        case "grep":           return .blue
        case "read":           return .cyan
        default:               return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(accentColor)
                        .frame(width: 14)
                    Text(tool.toolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                    Text(tool.args)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if tool.result != nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green.opacity(0.8))
                    } else {
                        ProgressView().scaleEffect(0.5)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.55))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().opacity(0.15).padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 4) {
                    if !tool.args.isEmpty {
                        Text("参数").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary.opacity(0.6))
                        Text(tool.args)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let result = tool.result {
                        Text("结果").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary.opacity(0.6)).padding(.top, 4)
                        Text(result)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .cornerRadius(7)
    }
}

// MARK: - Markdown 渲染

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundColor(.secondary)
                        renderedLine(Substring(line.dropFirst(2)))
                    }
                } else if !line.isEmpty {
                    renderedLine(Substring(line))
                } else {
                    Spacer().frame(height: 2)
                }
            }
        }
    }

    func renderedLine(_ raw: Substring) -> Text {
        segments(String(raw)).reduce(Text("")) { acc, seg in
            if seg.isBold {
                return acc + Text(seg.text).bold()
            } else if seg.isCode {
                return acc + Text(seg.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
            } else {
                return acc + Text(seg.text)
            }
        }
    }

    struct Seg { var text: String; var isBold = false; var isCode = false }

    func segments(_ s: String) -> [Seg] {
        var out: [Seg] = []
        var cur = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i...].hasPrefix("**") {
                if !cur.isEmpty { out.append(Seg(text: cur)); cur = "" }
                let st = s.index(i, offsetBy: 2)
                if let rng = s[st...].range(of: "**") {
                    out.append(Seg(text: String(s[st..<rng.lowerBound]), isBold: true))
                    i = rng.upperBound
                } else { cur += "**"; i = st }
            } else if s[i] == "`" {
                if !cur.isEmpty { out.append(Seg(text: cur)); cur = "" }
                let st = s.index(after: i)
                if let end = s[st...].firstIndex(of: "`") {
                    out.append(Seg(text: String(s[st..<end]), isCode: true))
                    i = s.index(after: end)
                } else { cur += "`"; i = s.index(after: i) }
            } else {
                cur.append(s[i]); i = s.index(after: i)
            }
        }
        if !cur.isEmpty { out.append(Seg(text: cur)) }
        return out
    }
}

// MARK: - NSTextView 输入框

struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void
    let maxLines: Int = 13

    static let editorFont: NSFont = .systemFont(ofSize: 14)
    static let singleLineHeight: CGFloat = {
        let lm = NSLayoutManager()
        return ceil(lm.defaultLineHeight(for: ChatTextEditor.editorFont))
    }()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = ChatTextEditor.editorFont
        tv.textColor = .labelColor
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 0)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.frame = NSRect(x: 0, y: 0, width: 100, height: ChatTextEditor.singleLineHeight)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextEditor
        init(_ parent: ChatTextEditor) { self.parent = parent }

        func updateHeight(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height
            let lineH = ChatTextEditor.singleLineHeight
            let maxH = lineH * CGFloat(parent.maxLines)
            DispatchQueue.main.async {
                self.parent.height = min(max(lineH, used), maxH)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            updateHeight(tv)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                    textView.string = ""
                    parent.text = ""
                    DispatchQueue.main.async {
                        self.parent.height = ChatTextEditor.singleLineHeight
                    }
                }
                return true
            }
            return false
        }
    }
}

// MARK: - 消息输入框

struct AgentInputView: View {
    @Environment(AppState.self) var appState
    @State private var inputText = ""
    @State private var editorHeight: CGFloat = ChatTextEditor.singleLineHeight

    func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !appState.isLoading else { return }
        inputText = ""
        editorHeight = ChatTextEditor.singleLineHeight
        appState.sendMessage(trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ChatTextEditor(text: $inputText, height: $editorHeight, onSubmit: submit)
                    .frame(height: editorHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                if inputText.isEmpty {
                    Text(appState.isLoading ? "等待响应中..." : "输入消息，按 Return 发送")
                        .font(.system(size: 14))
                        .foregroundColor(.primary.opacity(0.25))
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 0) {
                // 工作目录快捷按钮
                Button(action: { appState.selectWorkingDirectory() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder").font(.system(size: 10))
                        Text(appState.settings.workingDirectoryName)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
                    }
                    .foregroundColor(.primary.opacity(0.4))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

                Spacer()

                // 停止 / 发送按钮
                if appState.isLoading {
                    Button(action: { appState.cancelStream() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.75))
                                .frame(width: 18, height: 18)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(white: 0.12))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                } else {
                    Button(action: submit) {
                        ZStack {
                            Circle()
                                .fill(inputText.isEmpty
                                      ? Color.primary.opacity(0.2)
                                      : Color.primary.opacity(0.75))
                                .frame(width: 18, height: 18)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(white: 0.12))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(.bottom, 8)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - 文件面板

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let path: String
}

struct FilesPanel: View {
    @Binding var showFiles: Bool
    let session: AgentSession?
    @State private var searchText = ""
    @State private var fileItems: [FileItem] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil

    var filteredItems: [FileItem] {
        guard !searchText.isEmpty else { return fileItems }
        return fileItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var currentDir: String? { session?.workingDirectory }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("文件")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let dir = currentDir {
                    Text(URL(fileURLWithPath: dir).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(5)
                }
                // 刷新按钮
                if currentDir != nil {
                    Button(action: { if let d = currentDir { loadFiles(from: d) } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            Divider().opacity(0.2)

            // 搜索
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.55))
                TextField("过滤文件...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.05)).cornerRadius(5)
            .padding(.horizontal, 10).padding(.bottom, 4)

            Divider().opacity(0.2)

            if let dir = currentDir {
                if isLoading {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                    Spacer()
                } else if let err = loadError {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundColor(.orange.opacity(0.6))
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }.padding(.horizontal, 12)
                } else if filteredItems.isEmpty && !searchText.isEmpty {
                    VStack {
                        Spacer()
                        Text("无匹配文件")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                        Spacer()
                    }
                } else if fileItems.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "doc.badge.ellipsis")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary.opacity(0.25))
                        Text("目录为空")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                FileItemRow(item: item, rootDir: dir)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("未选择工作目录")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
            }
        }
        .onChange(of: currentDir) { _, newDir in
            fileItems = []
            loadError = nil
            if let dir = newDir { loadFiles(from: dir) }
        }
        .onAppear {
            if let dir = currentDir { loadFiles(from: dir) }
        }
    }

    func loadFiles(from dir: String) {
        isLoading = true
        loadError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.loadError = "路径不存在或不是目录"
                }
                return
            }
            do {
                let names = try fm.contentsOfDirectory(atPath: dir)
                let items = names
                    .filter { !$0.hasPrefix(".") }
                    .map { name -> FileItem in
                        let path = (dir as NSString).appendingPathComponent(name)
                        var d: ObjCBool = false
                        fm.fileExists(atPath: path, isDirectory: &d)
                        return FileItem(name: name, isDirectory: d.boolValue, path: path)
                    }
                    .sorted { a, b in
                        if a.isDirectory != b.isDirectory { return a.isDirectory }
                        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }
                DispatchQueue.main.async {
                    self.fileItems = items
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.loadError = "读取失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

struct FileItemRow: View {
    let item: FileItem
    let rootDir: String

    var icon: String {
        if item.isDirectory { return "folder" }
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "py": return "doc.text"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "md": return "text.alignleft"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    var iconColor: Color {
        if item.isDirectory { return .blue.opacity(0.75) }
        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "py": return .blue
        case "json", "yaml", "yml": return .green
        case "md": return .secondary
        default: return .secondary.opacity(0.7)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 14)
            Text(item.name)
                .font(.system(size: 12))
                .foregroundColor(item.isDirectory ? .primary.opacity(0.85) : .primary.opacity(0.7))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if !item.isDirectory {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: rootDir)
            }
        }
    }
}

// MARK: - 设置视图（中文）

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState
    @State private var selectedTab = "general"

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("设置").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            Divider().opacity(0.2)

            HStack(spacing: 0) {
                // 左侧导航
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(settingsTabs, id: \.id) { tab in
                        Button(action: { selectedTab = tab.id }) {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12))
                                    .frame(width: 16)
                                Text(tab.label).font(.system(size: 13))
                                Spacer()
                            }
                            .foregroundColor(selectedTab == tab.id ? .white : .primary.opacity(0.7))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedTab == tab.id ? Color.white.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 160)
                .padding(10)
                .background(Color.white.opacity(0.03))

                Divider().opacity(0.2)

                // 右侧内容
                ScrollView {
                    settingsContent(for: selectedTab)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }
        }
        .frame(width: 640, height: 480)
        .background(Color(white: 0.12))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    func settingsContent(for tab: String) -> some View {
        let settings = appState.settings
        switch tab {
        case "general":
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: "通用") {
                    SettingsToggleRow(
                        label: "自动压缩对话",
                        subtitle: "上下文接近限制时自动摘要",
                        isOn: Binding(get: { settings.autoCompact }, set: { settings.autoCompact = $0 })
                    )
                    SettingsToggleRow(
                        label: "通知",
                        subtitle: "任务完成时显示桌面通知",
                        isOn: Binding(get: { settings.notifications }, set: { settings.notifications = $0 })
                    )
                    SettingsToggleRow(
                        label: "音效",
                        subtitle: "代理完成时播放提示音",
                        isOn: Binding(get: { settings.soundEffects }, set: { settings.soundEffects = $0 })
                    )
                }
                SettingsSection(title: "工作目录") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前目录").font(.system(size: 13))
                            Text(settings.workingDirectory.isEmpty ? "未设置" : settings.workingDirectory)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("选择...") {
                            appState.selectWorkingDirectory()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                        .font(.system(size: 12))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    Divider().opacity(0.15).padding(.leading, 14)
                }
            }

        case "model":
            SettingsSection(title: "模型配置") {
                SettingsPickerRow(
                    label: "默认模型",
                    value: Binding(get: { settings.selectedModel }, set: { settings.selectedModel = $0 }),
                    options: ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]
                )
                SettingsPickerRow(
                    label: "思考模式",
                    value: Binding(get: { settings.thinkingMode }, set: { settings.thinkingMode = $0 }),
                    options: ["自动", "启用", "禁用"]
                )
                SettingsStepperRow(
                    label: "最大对话轮数",
                    subtitle: "每次请求的最大 agent 循环次数",
                    value: Binding(get: { settings.maxTurns }, set: { settings.maxTurns = $0 }),
                    range: 1...50
                )
            }

        case "keys":
            SettingsSection(title: "API 密钥") {
                SettingsSecureTextRow(
                    label: "Anthropic API 密钥",
                    placeholder: "sk-ant-...",
                    value: Binding(get: { settings.anthropicApiKey }, set: { settings.anthropicApiKey = $0 })
                )
            }
            Text("密钥存储在本地，仅用于覆盖环境变量中的 ANTHROPIC_API_KEY。\n如果已通过 claude 命令行配置，可留空。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 8)

        case "appearance":
            SettingsSection(title: "外观") {
                SettingsPickerRow(
                    label: "字体大小",
                    value: Binding(get: { settings.fontSize }, set: { settings.fontSize = $0 }),
                    options: ["12", "13", "14", "15", "16"]
                )
                SettingsToggleRow(
                    label: "紧凑模式",
                    subtitle: "减少消息列表间距",
                    isOn: Binding(get: { settings.compactMode }, set: { settings.compactMode = $0 })
                )
            }

        case "shortcuts":
            SettingsSection(title: "键盘快捷键") {
                SettingsShortcutRow(label: "发送消息", shortcut: "↵ Return")
                SettingsShortcutRow(label: "换行", shortcut: "⇧ Return")
                SettingsShortcutRow(label: "新建对话", shortcut: "⌘ N")
                SettingsShortcutRow(label: "切换侧边栏", shortcut: "⌘ \\")
                SettingsShortcutRow(label: "取消响应", shortcut: "⌘ .")
            }

        default:
            EmptyView()
        }
    }
}

private struct SettingsTab {
    let id: String; let label: String; let icon: String
}
private let settingsTabs: [SettingsTab] = [
    SettingsTab(id: "general",    label: "通用",     icon: "slider.horizontal.3"),
    SettingsTab(id: "model",      label: "模型",     icon: "cpu"),
    SettingsTab(id: "keys",       label: "API 密钥", icon: "key"),
    SettingsTab(id: "appearance", label: "外观",     icon: "paintbrush"),
    SettingsTab(id: "shortcuts",  label: "快捷键",   icon: "keyboard"),
]

// MARK: - 设置组件

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary).padding(.bottom, 10)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
        }
    }
}

struct SettingsToggleRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().scaleEffect(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        Divider().opacity(0.15).padding(.leading, 14)
    }
}

struct SettingsPickerRow: View {
    let label: String
    @Binding var value: String
    let options: [String]
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Picker("", selection: $value) {
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.system(size: 12))
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        Divider().opacity(0.15).padding(.leading, 14)
    }
}

struct SettingsStepperRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            Spacer()
            Stepper("\(value)", value: $value, in: range)
                .font(.system(size: 12))
                .frame(width: 120)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        Divider().opacity(0.15).padding(.leading, 14)
    }
}

struct SettingsSecureTextRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            SecureField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 200)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        Divider().opacity(0.15).padding(.leading, 14)
    }
}

struct SettingsShortcutRow: View {
    let label: String
    let shortcut: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.07))
                .cornerRadius(5)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        Divider().opacity(0.15).padding(.leading, 14)
    }
}

// MARK: - 调试日志视图

struct DebugLogView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "ladybug").foregroundColor(.green)
                Text("调试日志").font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("自动滚动", isOn: $autoScroll)
                    .toggleStyle(.switch).scaleEffect(0.75)
                    .labelsHidden()
                Text("自动滚动").font(.system(size: 12)).foregroundColor(.secondary)
                Button(action: { appState.clearLogs() }) {
                    Text("清空").font(.system(size: 12))
                        .foregroundColor(.orange)
                }.buttonStyle(.plain).padding(.leading, 8)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider().opacity(0.2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.debugLogs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timeString)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .frame(width: 90, alignment: .leading)

                                // 级别标签
                                Group {
                                    switch entry.level {
                                    case .debug:
                                        Text("DEBUG")
                                            .foregroundColor(.secondary)
                                    case .info:
                                        Text("INFO ")
                                            .foregroundColor(.green)
                                    case .error:
                                        Text("ERROR")
                                            .foregroundColor(.red)
                                    }
                                }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(width: 40, alignment: .leading)

                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.level == .error ? .red.opacity(0.9) : .primary.opacity(0.85))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 3)
                            .background(entry.level == .error ? Color.red.opacity(0.06) : Color.clear)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: appState.debugLogs.count) { _, _ in
                    if autoScroll, let last = appState.debugLogs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider().opacity(0.2)
            HStack {
                Text("\(appState.debugLogs.count) 条日志")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                if !appState.isClaudeInstalled {
                    Text("⚠️ claude 命令未找到").font(.system(size: 11)).foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 720, height: 480)
        .background(Color(white: 0.10))
        .preferredColorScheme(.dark)
    }
}

// MARK: - 预览

#Preview {
    ContentView()
        .environment(AppState())
        .preferredColorScheme(.dark)
        .frame(width: 1200, height: 760)
}
