import Foundation
import Observation

// MARK: - 应用设置（持久化到 UserDefaults）

@Observable
class AppSettings {
    static let shared = AppSettings()

    // MARK: 通用
    var autoCompact: Bool = UserDefaults.standard.bool(forKey: "autoCompact") {
        didSet { UserDefaults.standard.set(autoCompact, forKey: "autoCompact") }
    }
    var notifications: Bool = UserDefaults.standard.bool(forKey: "notifications") {
        didSet { UserDefaults.standard.set(notifications, forKey: "notifications") }
    }
    var soundEffects: Bool = UserDefaults.standard.bool(forKey: "soundEffects") {
        didSet { UserDefaults.standard.set(soundEffects, forKey: "soundEffects") }
    }

    // MARK: 模型
    var selectedModel: String = {
        UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-sonnet-4-6"
    }() {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }
    var thinkingMode: String = {
        UserDefaults.standard.string(forKey: "thinkingMode") ?? "自动"
    }() {
        didSet { UserDefaults.standard.set(thinkingMode, forKey: "thinkingMode") }
    }
    var maxTurns: Int = {
        let v = UserDefaults.standard.integer(forKey: "maxTurns")
        return v == 0 ? 10 : v
    }() {
        didSet { UserDefaults.standard.set(maxTurns, forKey: "maxTurns") }
    }

    // MARK: API 密钥
    var anthropicApiKey: String = {
        UserDefaults.standard.string(forKey: "anthropicApiKey") ?? ""
    }() {
        didSet { UserDefaults.standard.set(anthropicApiKey, forKey: "anthropicApiKey") }
    }

    // MARK: 工作目录
    var workingDirectory: String = {
        UserDefaults.standard.string(forKey: "workingDirectory") ?? ""
    }() {
        didSet { UserDefaults.standard.set(workingDirectory, forKey: "workingDirectory") }
    }

    var effectiveWorkingDirectory: String? {
        workingDirectory.isEmpty ? nil : workingDirectory
    }

    var workingDirectoryName: String {
        guard !workingDirectory.isEmpty else { return "未选择目录" }
        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    // MARK: 外观
    var fontSize: String = {
        UserDefaults.standard.string(forKey: "fontSize") ?? "14"
    }() {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    var compactMode: Bool = UserDefaults.standard.bool(forKey: "compactMode") {
        didSet { UserDefaults.standard.set(compactMode, forKey: "compactMode") }
    }

    private init() {}
}
