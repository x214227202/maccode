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

/// 消息角色：与 clui-cc 对齐，tool 单独一类
enum MessageRole { case user, assistant, tool }

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
    case thinking(String)
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
                                    // 再次点击已展开项目 → 仅收起折叠，不清除会话（保持中间区域不变）
                                    appState.selectedProjectId = nil
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
                            // 极短暂出现：用户消息已加，助手占位尚未添加时
                            if appState.isLoading && appState.currentMessages.last?.role == .user {
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(claudeAvatarGradient)
                                        .frame(width: 26, height: 26)
                                        .overlay(Image(systemName: "asterisk")
                                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                                        .padding(.top, 3)
                                    StreamingDotsView()
                                        .padding(.horizontal, 18).padding(.vertical, 14)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16)
                                            .stroke(assistBubbleBorder, lineWidth: 1))
                                    Spacer(minLength: 52)
                                }
                                .padding(.bottom, 16)
                                .id("streaming-placeholder")
                            }
                            // 底部锚点，用于滚动定位
                            Color.clear.frame(height: 1).id("__bottom__")
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                    // 切换会话时立刻滚到底部
                    .onAppear {
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                    .onChange(of: appState.selectedSessionId) { _, _ in
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                    .onChange(of: appState.currentMessages.count) { _, _ in
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                    .onChange(of: appState.streamingVersion) { _, _ in
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                    .onChange(of: appState.isLoading) { _, _ in
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                }
            }

            // 实时活动状态条
            if appState.isLoading {
                LiveActivityBar()
                    .padding(.horizontal, 80)
                    .padding(.top, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 输入框
            AgentInputView()
                .padding(.horizontal, 80)
                .padding(.top, 4)
                .padding(.bottom, 14)
        }
        .inspector(isPresented: $showFiles) {
            FilesPanel(showFiles: $showFiles, session: appState.selectedSession)
                .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
        }
    }
}

// MARK: - 实时活动状态条

struct LiveActivityBar: View {
    @Environment(AppState.self) var appState

    @State private var pulse = false
    @State private var dotPhase: Int = 0

    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    // ── 根据 kind 决定颜色/图标 ──────────────────────────
    private var kindColor: Color {
        switch appState.liveActivityKind {
        case .connecting: return Color(red: 0.9, green: 0.65, blue: 0.1)   // 琥珀
        case .thinking:   return Color(red: 0.65, green: 0.35, blue: 0.95) // 紫
        case .toolUse:    return Color(red: 0.25, green: 0.55, blue: 1.0)   // 蓝
        case .generating: return Color(red: 0.2, green: 0.78, blue: 0.55)  // 青绿
        case .toolDone:   return Color(red: 0.3, green: 0.82, blue: 0.45)  // 绿
        }
    }
    private var kindIcon: String {
        switch appState.liveActivityKind {
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .thinking:   return "brain.fill"
        case .toolUse:    return "wrench.and.screwdriver.fill"
        case .generating: return "sparkles"
        case .toolDone:   return "checkmark.circle.fill"
        }
    }
    private var kindLabel: String {
        switch appState.liveActivityKind {
        case .connecting: return "连接中"
        case .thinking:
            let mode = appState.settings.thinkingMode
            switch mode {
            case "启用": return "深度思考"
            case "禁用": return "快速思考"
            default:     return "自动思考"
            }
        case .toolUse:    return "工具调用"
        case .generating: return "生成中"
        case .toolDone:   return "已完成"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 主行 ──────────────────────────────────────
            HStack(spacing: 8) {
                // 脉冲图标
                ZStack {
                    Circle()
                        .fill(kindColor.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                    Image(systemName: kindIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(kindColor)
                }
                .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)

                // 模式标签
                Text(kindLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(kindColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(kindColor.opacity(0.12))
                    .cornerRadius(5)

                // 活动文字
                let shown = appState.liveActivity.isEmpty ? "Claude 正在处理..." : appState.liveActivity
                Text(shown + dotStr)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.72))
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.15), value: shown)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)

            // ── 思考片段预览（仅思考阶段显示）───────────────
            if appState.isThinking && !appState.thinkingSnippet.isEmpty {
                Divider()
                    .opacity(0.12)
                    .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    Rectangle()
                        .fill(kindColor.opacity(0.5))
                        .frame(width: 2)
                        .cornerRadius(1)
                    Text(appState.thinkingSnippet)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.65))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(kindColor.opacity(0.28), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.25), value: appState.liveActivityKind == .thinking)
        .onAppear { pulse = true }
        .onReceive(timer) { _ in dotPhase = (dotPhase + 1) % 4 }
    }

    private var dotStr: String { String(repeating: ".", count: dotPhase) }
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

// MARK: - 气泡颜色常量

/// 用户气泡：金色渐变描边
private let userBubbleBorder = LinearGradient(
    colors: [
        Color(red: 1.0, green: 0.86, blue: 0.28).opacity(0.90),
        Color(red: 0.90, green: 0.62, blue: 0.00).opacity(0.55)
    ],
    startPoint: .topLeading, endPoint: .bottomTrailing
)
private let userBubbleFill = Color(red: 1.0, green: 0.80, blue: 0.10).opacity(0.08)

/// 助手气泡：蓝色渐变描边
private let assistBubbleBorder = LinearGradient(
    colors: [
        Color(red: 0.45, green: 0.68, blue: 1.00).opacity(0.70),
        Color(red: 0.20, green: 0.47, blue: 0.92).opacity(0.40)
    ],
    startPoint: .topLeading, endPoint: .bottomTrailing
)
private let assistBubbleFill = Color(red: 0.25, green: 0.52, blue: 1.00).opacity(0.06)

/// Claude 头像渐变（橙红）
private let claudeAvatarGradient = LinearGradient(
    colors: [Color(red: 0.95, green: 0.38, blue: 0.25), Color(red: 0.85, green: 0.25, blue: 0.15)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

// MARK: - 流式加载波浪动画

struct StreamingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.45, green: 0.72, blue: 1.0),
                                     Color(red: 0.25, green: 0.50, blue: 0.95)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 7, height: 7)
                    .offset(y: phase ? -4 : 3)
                    .opacity(phase ? 0.95 : 0.30)
                    .animation(
                        .easeInOut(duration: 0.50)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.17),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: - 聊天消息视图

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:       UserBubbleView(message: message)
        case .assistant:  AssistantBubbleView(message: message)
        case .tool:       ToolMessageView(message: message)
        }
    }
}

// MARK: 用户气泡（金色，靠右）

// MARK: 用户气泡（金色线框，靠右，无底色）

struct UserBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 72)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    Group {
                        if case .text(let t) = block, !t.isEmpty {
                            Text(t)
                                .font(.system(size: 13))
                                .lineSpacing(3.5)
                                .foregroundColor(.primary.opacity(0.92))
                                .textSelection(.enabled)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(userBubbleBorder, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }
}

// MARK: 助手气泡（蓝色线框，靠左，无底色，仅含文字/思考）

struct AssistantBubbleView: View {
    let message: ChatMessage

    private var isStreamingPlaceholder: Bool {
        guard message.blocks.count == 1,
              case .text(let t) = message.blocks[0] else { return false }
        return t.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Claude 头像
            RoundedRectangle(cornerRadius: 7)
                .fill(claudeAvatarGradient)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "asterisk")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
                .padding(.top, 3)

            Group {
                if isStreamingPlaceholder {
                    StreamingDotsView()
                        .padding(.horizontal, 18).padding(.vertical, 14)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                            Group {
                                switch block {
                                case .text(let t):
                                    if !t.isEmpty {
                                        MarkdownText(text: t)
                                            .font(.system(size: 13))
                                            .lineSpacing(3.5)
                                            .textSelection(.enabled)
                                    }
                                case .thinking(let t):
                                    ThinkingBlockView(text: t)
                                case .toolCall:
                                    EmptyView() // 工具调用已是独立消息，不在此渲染
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(assistBubbleBorder, lineWidth: 1)
            )

            Spacer(minLength: 52)
        }
        .padding(.bottom, 8)
    }
}

// MARK: 工具执行消息（独立于对话气泡，对齐至助手内容区）

struct ToolMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 占位宽度与头像对齐（26pt 头像 + 10pt 间距 = 36pt）
            Color.clear.frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    Group {
                        if case .toolCall(let tc) = block {
                            ToolExecutionCard(tool: tc)
                        }
                    }
                }
            }
            Spacer(minLength: 52)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - 工具执行卡片（代码/操作数据流）

struct ToolExecutionCard: View {
    let tool: ToolCallBlock
    @State private var expanded = false

    var isRunning: Bool { tool.result == nil }

    /// 运行中：琥珀色；完成：绿色
    var cardBorder: LinearGradient {
        isRunning
            ? LinearGradient(
                colors: [Color(red: 0.95, green: 0.65, blue: 0.10).opacity(0.85),
                         Color(red: 0.85, green: 0.48, blue: 0.00).opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [Color(red: 0.28, green: 0.82, blue: 0.46).opacity(0.75),
                         Color(red: 0.14, green: 0.64, blue: 0.34).opacity(0.48)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var cardFill: Color {
        isRunning
            ? Color(red: 0.95, green: 0.60, blue: 0.10).opacity(0.04)
            : Color(red: 0.18, green: 0.78, blue: 0.38).opacity(0.04)
    }

    var toolIcon: String {
        switch tool.toolName.lowercased() {
        case "read":                   return "doc.text"
        case "write":                  return "square.and.pencil"
        case "edit", "multiedit":      return "pencil.and.outline"
        case "bash":                   return "terminal"
        case "grep", "search":         return "magnifyingglass"
        case "glob":                   return "folder"
        case "webfetch", "websearch":  return "globe"
        case "todoread", "todowrite":  return "checklist"
        case "task":                   return "cpu"
        default:                       return "wrench.and.screwdriver"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部行
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            }) {
                HStack(spacing: 8) {
                    // 状态：进度 or 完成对勾
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.52)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.26, green: 0.76, blue: 0.42))
                    }

                    // 工具图标
                    Image(systemName: toolIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.65))
                        .frame(width: 14)

                    // 工具名（等宽，醒目）
                    Text(tool.toolName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.82))

                    // 参数预览
                    if !tool.args.isEmpty {
                        Text(tool.args)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.60))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            // 展开详情
            if expanded {
                Divider().opacity(0.10).padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 8) {
                    if !tool.args.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("INPUT")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.42))
                            Text(tool.args)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.78))
                                .textSelection(.enabled)
                        }
                    }
                    if let result = tool.result {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OUTPUT")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.42))
                            let preview = result.count > 700
                                ? String(result.prefix(700)) + "\n…（已截断，共 \(result.count) 字）"
                                : result
                            Text(preview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.82))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Markdown 渲染

struct MarkdownText: View {
    let text: String

    enum TextSegment { case prose(String); case code(String, language: String) }

    // 缓存解析结果，text 不变时复用，避免每次渲染都重新扫描全文
    @State private var cachedText: String = ""
    @State private var cachedSegments: [TextSegment] = []

    private func parseSegments(_ raw: String) -> [TextSegment] {
        var result: [TextSegment] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        var proseBuf: [String] = []
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                if !proseBuf.isEmpty {
                    result.append(.prose(proseBuf.joined(separator: "\n")))
                    proseBuf = []
                }
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                result.append(.code(codeLines.joined(separator: "\n"), language: lang))
            } else {
                proseBuf.append(line)
                i += 1
            }
        }
        if !proseBuf.isEmpty { result.append(.prose(proseBuf.joined(separator: "\n"))) }
        return result
    }

    var body: some View {
        let segs: [TextSegment]
        if text == cachedText {
            segs = cachedSegments
        } else {
            segs = parseSegments(text)
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .prose(let t): ProseView(text: t)
                case .code(let code, let lang): CodeBlockView(code: code, language: lang)
                }
            }
        }
        .onAppear { cachedText = text; cachedSegments = segs }
        .onChange(of: text) { _, newText in
            cachedText = newText
            cachedSegments = parseSegments(newText)
        }
    }
}

// MARK: - Prose（段落式 Markdown 排版）

struct ProseView: View {
    let text: String

    // ── 节点类型 ──────────────────────────────────────────
    private enum Node {
        case heading(level: Int, content: String)
        case paragraph(String)          // 多行合并为一段
        case bullet(String)             // - * + 列表项
        case numbered(n: Int, String)   // 1. 2. 有序列表
        case rule                       // --- 水平分割线
        case blank                      // 空行（已去重）
        case table(header: [String], rows: [[String]])  // Markdown 表格

        var isBlank: Bool { if case .blank = self { return true }; return false }
    }

    // ── 解析 ──────────────────────────────────────────────
    private func parse(_ raw: String) -> [Node] {
        var nodes: [Node] = []
        var para: [String] = []

        func flushPara() {
            guard !para.isEmpty else { return }
            nodes.append(.paragraph(para.joined(separator: "\n")))
            para = []
        }
        func addBlank() {
            flushPara()
            if !(nodes.last?.isBlank ?? false) { nodes.append(.blank) }
        }

        let rawLines = raw.components(separatedBy: "\n")
        var li = 0
        while li < rawLines.count {
            let line = rawLines[li]
            // ── 表格检测：连续以 | 开头/包含 | 的行 ─────────
            if isTableRow(line) {
                flushPara()
                var tableLines: [String] = [line]
                li += 1
                while li < rawLines.count && isTableRow(rawLines[li]) {
                    tableLines.append(rawLines[li])
                    li += 1
                }
                if let tbl = parseTable(tableLines) { nodes.append(tbl) }
                continue
            }
            if line.hasPrefix("### ") {
                flushPara(); nodes.append(.heading(level: 3, content: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushPara(); nodes.append(.heading(level: 2, content: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushPara(); nodes.append(.heading(level: 1, content: String(line.dropFirst(2))))
            } else if line == "---" || line == "***" || line == "___" {
                flushPara(); nodes.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushPara(); nodes.append(.bullet(String(line.dropFirst(2))))
            } else if let (n, content) = parseNumbered(line) {
                flushPara(); nodes.append(.numbered(n: n, content))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                addBlank()
            } else {
                para.append(line)
            }
            li += 1
        }
        flushPara()
        // 去掉首尾空行
        return nodes.drop(while: { $0.isBlank })
                    .reversed().drop(while: { $0.isBlank })
                    .reversed() as [Node]
    }

    // ── 表格辅助 ─────────────────────────────────────────
    private func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") || (t.contains("|") && !t.hasPrefix("#"))
    }

    private func splitCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t = String(t.dropFirst()) }
        if t.hasSuffix("|") { t = String(t.dropLast()) }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isSeparatorRow(_ line: String) -> Bool {
        splitCells(line).allSatisfy { cell in
            let c = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
            return c.isEmpty || c.allSatisfy { $0 == "-" }
        }
    }

    private func parseTable(_ lines: [String]) -> Node? {
        guard lines.count >= 1 else { return nil }
        var filtered = lines
        // 找到分隔行（--- 行）并移除
        if filtered.count >= 2 && isSeparatorRow(filtered[1]) {
            filtered.remove(at: 1)
        }
        guard !filtered.isEmpty else { return nil }
        let header = splitCells(filtered[0])
        let rows = filtered.dropFirst().map { splitCells($0) }
        return .table(header: header, rows: Array(rows))
    }

    private func parseNumbered(_ line: String) -> (Int, String)? {
        var i = line.startIndex
        var numStr = ""
        while i < line.endIndex && line[i].isNumber { numStr.append(line[i]); i = line.index(after: i) }
        guard !numStr.isEmpty,
              i < line.endIndex, line[i] == ".",
              let after = line.index(i, offsetBy: 1, limitedBy: line.endIndex), after < line.endIndex,
              line[after] == " ",
              let n = Int(numStr) else { return nil }
        let content = String(line[line.index(after, offsetBy: 1)...])
        return content.isEmpty ? nil : (n, content)
    }

    // ── 渲染 ──────────────────────────────────────────────
    var body: some View {
        let nodes = parse(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { idx, node in
                nodeView(node)
                    .padding(.bottom, bottomPad(nodes, idx))
            }
        }
    }

    private func bottomPad(_ nodes: [Node], _ i: Int) -> CGFloat {
        guard i < nodes.count - 1 else { return 0 }
        let cur = nodes[i]; let nxt = nodes[i + 1]
        switch cur {
        case .blank:   return 0
        case .rule:    return 8
        case .heading(let lv, _):
            return lv == 1 ? 8 : 5
        case .bullet, .numbered:
            switch nxt { case .bullet, .numbered: return 4; default: return 8 }
        case .paragraph:
            switch nxt { case .heading: return 14; case .blank: return 0; default: return 8 }
        case .table:
            return 10
        }
    }

    @ViewBuilder
    private func nodeView(_ node: Node) -> some View {
        switch node {

        case .heading(let level, let content):
            VStack(alignment: .leading, spacing: 4) {
                inline(content)
                    .font(.system(
                        size: level == 1 ? 16 : level == 2 ? 14 : 13,
                        weight: level == 1 ? .bold : .semibold
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                if level <= 2 {
                    Rectangle().fill(Color.secondary.opacity(0.14)).frame(height: 1)
                }
            }

        case .paragraph(let t):
            inline(t)
                .font(.system(size: 13))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let content):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 12, alignment: .center)
                    .padding(.top, 0.5)
                inline(content)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let n, let content):
            HStack(alignment: .top, spacing: 6) {
                Text("\(n).")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.65))
                    .frame(minWidth: 20, alignment: .trailing)
                    .padding(.top, 0.5)
                inline(content)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .blank:
            Color.clear.frame(height: 6)

        case .table(let header, let rows):
            TableView(header: header, rows: rows)
        }
    }

    // ── 行内标记：**bold** *italic* `code` ────────────────
    private func inline(_ raw: String) -> Text {
        var result = Text("")
        var buf = ""
        var i = raw.startIndex

        func flush() { if !buf.isEmpty { result = result + Text(buf); buf = "" } }

        while i < raw.endIndex {
            if raw[i...].hasPrefix("**") {
                flush()
                let st = raw.index(i, offsetBy: 2)
                if let rng = raw[st...].range(of: "**") {
                    result = result + Text(String(raw[st..<rng.lowerBound])).bold()
                    i = rng.upperBound
                } else { buf += "**"; i = st }
            } else if raw[i] == "*" {
                flush()
                let st = raw.index(after: i)
                if let end = raw[st...].firstIndex(of: "*") {
                    result = result + Text(String(raw[st..<end])).italic()
                    i = raw.index(after: end)
                } else { buf += "*"; i = raw.index(after: i) }
            } else if raw[i] == "`" {
                flush()
                let st = raw.index(after: i)
                if let end = raw[st...].firstIndex(of: "`") {
                    result = result + Text(String(raw[st..<end]))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.88))
                    i = raw.index(after: end)
                } else { buf += "`"; i = raw.index(after: i) }
            } else {
                buf.append(raw[i]); i = raw.index(after: i)
            }
        }
        flush()
        return result
    }
}

// MARK: - 表格视图

struct TableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                ForEach(Array(header.enumerated()), id: \.offset) { idx, cell in
                    Text(cell)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    if idx < header.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                    }
                }
            }
            .background(Color.white.opacity(0.07))

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

            // 数据行
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    let colCount = max(header.count, row.count)
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        let cell = colIdx < row.count ? row[colIdx] : ""
                        Text(cell)
                            .font(.system(size: 11.5))
                            .foregroundColor(.primary.opacity(0.80))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        if colIdx < colCount - 1 {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                        }
                    }
                }
                .background(rowIdx % 2 == 0 ? Color.clear : Color.white.opacity(0.025))

                if rowIdx < rows.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
            }
        }
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - 代码块视图

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 语言标头 + 复制按钮
            HStack {
                Text(language.isEmpty ? "代码" : language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.55))
                Spacer()
                Button(action: copyCode) {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "已复制" : "复制")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.04))

            Divider().opacity(0.12)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .background(Color.black.opacity(0.32))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - 思考过程块

struct ThinkingBlockView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }) {
                HStack(spacing: 7) {
                    Image(systemName: "brain.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.purple.opacity(0.75))
                    Text("思考过程")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.purple.opacity(0.7))
                    Text("(\(text.count) 字)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.45))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().opacity(0.15).padding(.horizontal, 10)
                ScrollView {
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.75))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 220)
            }
        }
        .background(Color.purple.opacity(0.07))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.purple.opacity(0.18), lineWidth: 1))
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
    var depth: Int = 0
}

struct FilesPanel: View {
    @Binding var showFiles: Bool
    let session: AgentSession?
    @State private var searchText = ""
    @State private var rootItems: [FileItem] = []
    @State private var expandedPaths: Set<String> = []
    @State private var childrenByPath: [String: [FileItem]] = [:]
    @State private var loadingPaths: Set<String> = []
    @State private var isLoadingRoot = false
    @State private var loadError: String? = nil

    var currentDir: String? { session?.workingDirectory }

    // 递归构建当前可见的扁平列表
    func buildVisible(_ items: [FileItem]) -> [FileItem] {
        var result: [FileItem] = []
        for item in items {
            result.append(item)
            if item.isDirectory && expandedPaths.contains(item.path) {
                if let children = childrenByPath[item.path] {
                    result.append(contentsOf: buildVisible(children))
                }
            }
        }
        return result
    }

    var visibleItems: [FileItem] { buildVisible(rootItems) }

    var filteredItems: [FileItem] {
        guard !searchText.isEmpty else { return visibleItems }
        return visibleItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

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
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let displayPath = dir.hasPrefix(home)
                        ? "~" + dir.dropFirst(home.count)
                        : dir
                    Text(displayPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(5)
                        .help(dir)
                }
                if currentDir != nil {
                    Button(action: { reloadRoot() }) {
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
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.05)).cornerRadius(5)
            .padding(.horizontal, 10).padding(.bottom, 4)

            Divider().opacity(0.2)

            if let dir = currentDir {
                if isLoadingRoot {
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                    Spacer()
                } else if let err = loadError {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20)).foregroundColor(.orange.opacity(0.6))
                        Text(err).font(.system(size: 11)).foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }.padding(.horizontal, 12)
                } else if filteredItems.isEmpty && !searchText.isEmpty {
                    VStack {
                        Spacer()
                        Text("无匹配文件").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.4))
                        Spacer()
                    }
                } else if rootItems.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "doc.badge.ellipsis")
                            .font(.system(size: 22)).foregroundColor(.secondary.opacity(0.25))
                        Text("目录为空").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.4))
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                FileItemRow(
                                    item: item,
                                    rootDir: dir,
                                    isExpanded: expandedPaths.contains(item.path),
                                    isLoadingChildren: loadingPaths.contains(item.path),
                                    onToggle: { toggleDirectory(item) }
                                )
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24)).foregroundColor(.secondary.opacity(0.4))
                    Text("未选择工作目录")
                        .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
            }
        }
        .onChange(of: currentDir) { _, newDir in
            resetTree()
            if let dir = newDir { loadRootItems(from: dir) }
        }
        .onAppear {
            if let dir = currentDir { loadRootItems(from: dir) }
        }
    }

    func reloadRoot() {
        resetTree()
        if let dir = currentDir { loadRootItems(from: dir) }
    }

    func resetTree() {
        rootItems = []
        expandedPaths = []
        childrenByPath = [:]
        loadingPaths = []
        loadError = nil
    }

    func toggleDirectory(_ item: FileItem) {
        guard item.isDirectory else { return }
        if expandedPaths.contains(item.path) {
            // 折叠：移除该目录及其所有子目录
            let prefix = item.path + "/"
            expandedPaths = expandedPaths.filter { $0 != item.path && !$0.hasPrefix(prefix) }
        } else {
            expandedPaths.insert(item.path)
            if childrenByPath[item.path] == nil && !loadingPaths.contains(item.path) {
                loadChildren(of: item)
            }
        }
    }

    func loadChildren(of parent: FileItem) {
        let path = parent.path
        let depth = parent.depth + 1
        loadingPaths.insert(path)
        Task { @MainActor in
            let items = await Task.detached(priority: .userInitiated) {
                loadDirItems(path, depth: depth)
            }.value
            childrenByPath[path] = items
            loadingPaths.remove(path)
        }
    }

    func loadRootItems(from dir: String) {
        isLoadingRoot = true
        loadError = nil
        Task { @MainActor in
            // (items, errorMessage) — nil items 表示出错
            let (items, errMsg): ([FileItem]?, String?) = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                    return (nil, "路径不存在或不是目录")
                }
                return (loadDirItems(dir, depth: 0), nil)
            }.value
            if let items {
                rootItems = items
            } else {
                loadError = errMsg
            }
            isLoadingRoot = false
        }
    }
}

// 从磁盘读取目录内容（可在后台线程调用）
private nonisolated func loadDirItems(_ dir: String, depth: Int) -> [FileItem] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
    return names
        .filter { !$0.hasPrefix(".") }
        .map { name -> FileItem in
            let path = (dir as NSString).appendingPathComponent(name)
            var d: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &d)
            return FileItem(name: name, isDirectory: d.boolValue, path: path, depth: depth)
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
}

struct FileItemRow: View {
    let item: FileItem
    let rootDir: String
    let isExpanded: Bool
    let isLoadingChildren: Bool
    let onToggle: () -> Void

    var fileIcon: String {
        if item.isDirectory { return isExpanded ? "folder.fill" : "folder" }
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
        if item.isDirectory { return .blue.opacity(isExpanded ? 0.95 : 0.75) }
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
        HStack(spacing: 0) {
            // 缩进
            Spacer().frame(width: CGFloat(item.depth) * 14 + 4)

            // 目录展开/折叠按钮
            if item.isDirectory {
                Button(action: onToggle) {
                    Group {
                        if isLoadingChildren {
                            ProgressView().scaleEffect(0.45)
                        } else {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.55))
                        }
                    }
                    .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

            Spacer().frame(width: 4)

            Image(systemName: fileIcon)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 14)

            Spacer().frame(width: 5)

            Text(item.name)
                .font(.system(size: 12))
                .foregroundColor(item.isDirectory ? .primary.opacity(0.85) : .primary.opacity(0.72))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory {
                onToggle()
            } else {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: rootDir)
            }
        }
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            }
            if !item.isDirectory {
                Button("用默认程序打开") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
                }
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
