# maccode

> 一个基于 [ClaudeCodeSDK](https://github.com/jamesrochabrun/ClaudeCodeSDK) 构建的 macOS 本地 Claude Code 图形界面客户端。

[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## 截图

> _(运行后截图放这里)_

---

## 功能特性

- **原生 macOS 界面** — 纯 SwiftUI，深色模式，三栏布局（会话列表 / 对话 / 文件）
- **真实 Claude Code 集成** — 通过 ClaudeCodeSDK 调用本地 `claude` CLI
- **流式响应** — 实时显示连接状态、工具执行进度、最终结果
- **会话管理** — 自动加载 `~/.claude/projects/` 中的历史会话，支持恢复对话
- **工作目录选择** — 可为每个对话绑定不同项目目录
- **停止 / 取消** — 随时中断正在进行的请求
- **持久化设置** — 模型选择、API 密钥、最大轮数等配置持久保存
- **完整中文界面** — 所有设置页面使用中文

---

## 系统要求

| 项目 | 要求 |
|------|------|
| macOS | 13.0 Ventura 及以上 |
| Xcode | 16.0 及以上 |
| Claude Code CLI | 已安装（见下方） |

---

## 安装步骤

### 1. 安装 Claude Code CLI

```bash
npm install -g @anthropic/claude-code
```

安装完成后验证：

```bash
claude --version
```

### 2. 克隆项目

```bash
git clone https://github.com/x214227202/maccode.git
cd maccode
```

### 3. 解压 SDK（首次使用需要）

项目使用 [ClaudeCodeSDK 1.2.4](https://github.com/jamesrochabrun/ClaudeCodeSDK) 作为本地依赖。  
请将 `ClaudeCodeSDK-1.2.4.zip` 解压到项目父目录：

```
code.ui/
├── maccode/               # 本项目
└── ClaudeCodeSDK_extracted/
    └── ClaudeCodeSDK-1.2.4/   # SDK 解压位置
```

或直接克隆 SDK：

```bash
# 在 maccode 的上级目录执行
mkdir -p ClaudeCodeSDK_extracted
cd ClaudeCodeSDK_extracted
git clone --branch 1.2.4 https://github.com/jamesrochabrun/ClaudeCodeSDK ClaudeCodeSDK-1.2.4
```

### 4. 用 Xcode 打开并运行

```bash
open maccode.xcodeproj
```

在 Xcode 中按 `⌘R` 运行即可。

---

## 配置

首次运行后，点击左下角齿轮图标 ⚙️ 打开设置：

- **通用** — 自动压缩、通知、音效
- **模型** — 选择默认模型（Opus / Sonnet / Haiku）、最大对话轮数
- **API 密钥** — 可选填 Anthropic API 密钥（也可通过环境变量 `ANTHROPIC_API_KEY` 配置）
- **工作目录** — 为 Claude 指定项目根目录

---

## 使用方法

1. 点击「**新建对话**」创建会话
2. 点击头部文件夹图标选择工作目录（或在设置中全局配置）
3. 在输入框输入任务描述，按 `Return` 发送
4. 使用 `Shift+Return` 换行
5. 点击 ■ 停止按钮可随时取消响应

---

## 项目结构

```
maccode/
├── maccode.xcodeproj/          # Xcode 项目配置
└── maccode/
    ├── maccodeApp.swift        # App 入口，注入 AppState
    ├── AppState.swift          # 核心状态管理 + ClaudeCodeSDK 集成
    ├── AppSettings.swift       # 持久化设置（UserDefaults）
    └── ContentView.swift       # 全部 UI 实现
```

---

## 开源引用

本项目基于以下开源项目构建，对原作者表示感谢：

| 项目 | 作者 | 许可证 |
|------|------|--------|
| [ClaudeCodeSDK](https://github.com/jamesrochabrun/ClaudeCodeSDK) | [@jamesrochabrun](https://github.com/jamesrochabrun) | MIT |
| [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) | [@jamesrochabrun](https://github.com/jamesrochabrun) | MIT |

Claude Code 是 [Anthropic](https://anthropic.com) 的产品。

---

## 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本项目
2. 创建功能分支：`git checkout -b feature/your-feature`
3. 提交更改：`git commit -m 'Add some feature'`
4. 推送分支：`git push origin feature/your-feature`
5. 提交 Pull Request

---

## 许可证

本项目采用 [MIT License](LICENSE) 开源协议。

---

## 作者

**x214227202** — 如有问题请提交 [Issue](https://github.com/x214227202/maccode/issues)
