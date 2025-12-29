import Foundation

// MARK: - TriggerSound

/// 触发音效 - 触发时播放的系统音效
public enum TriggerSound: String, CaseIterable, Codable {
    case none = "无"
    case tink = "Tink"
    case pop = "Pop"
    case ping = "Ping"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case hero = "Hero"

    public var displayName: String {
        return rawValue
    }

    /// 系统音效名称（用于 NSSound）
    public var systemName: String? {
        switch self {
        case .none: return nil
        default: return rawValue
        }
    }
}

// MARK: - TriggerScope

/// 触发范围 - 控制触发词在哪些应用中生效
public enum TriggerScope: Int, CaseIterable, Codable {
    case kittyOnly = 0      // 仅 kitty 终端
    case terminalsOnly = 1  // 仅终端类应用（kitty + Terminal.app）
    case allApps = 2        // 所有应用

    public var displayName: String {
        switch self {
        case .kittyOnly: return "仅 Kitty"
        case .terminalsOnly: return "仅终端"
        case .allApps: return "所有应用"
        }
    }

    public var description: String {
        switch self {
        case .kittyOnly: return "只在 Kitty 终端中触发"
        case .terminalsOnly: return "在 Kitty 和 Terminal.app 中触发"
        case .allApps: return "在所有应用中触发（包括浏览器、备忘录等）"
        }
    }
}

// MARK: - SettingsManager

/// 设置管理器 - 管理应用设置的持久化
public class SettingsManager: SettingsManagerProtocol {
    private let userDefaults: UserDefaults
    private var callbacks: [UUID: () -> Void] = [:]

    private enum Keys {
        static let enabled = "voiceenter.enabled"
        static let triggerWords = "voiceenter.triggerWords"
        static let triggerScope = "voiceenter.triggerScope"
        static let triggerSound = "voiceenter.triggerSound"
    }

    private static let defaultTriggerWords = ["发送", "Go"]
    private static let maxTriggerWordLength = 10

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var isEnabled: Bool {
        get {
            // 默认值为 true
            if userDefaults.object(forKey: Keys.enabled) == nil {
                return true
            }
            return userDefaults.bool(forKey: Keys.enabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.enabled)
            notifyCallbacks()
        }
    }

    public var triggerWords: [String] {
        if let words = userDefaults.stringArray(forKey: Keys.triggerWords) {
            return words
        }
        return Self.defaultTriggerWords
    }

    public var triggerScope: TriggerScope {
        get {
            let rawValue = userDefaults.integer(forKey: Keys.triggerScope)
            return TriggerScope(rawValue: rawValue) ?? .kittyOnly
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.triggerScope)
            notifyCallbacks()
        }
    }

    public var triggerSound: TriggerSound {
        get {
            if let rawValue = userDefaults.string(forKey: Keys.triggerSound),
               let sound = TriggerSound(rawValue: rawValue) {
                return sound
            }
            return .tink  // 默认使用 Tink 音效
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Keys.triggerSound)
            notifyCallbacks()
        }
    }

    @discardableResult
    public func addTriggerWord(_ word: String) -> Bool {
        // 去除首尾空格
        let trimmedWord = word.trimmingCharacters(in: .whitespaces)

        // 验证：不能为空
        guard !trimmedWord.isEmpty else { return false }

        // 验证：不能超过最大长度
        guard trimmedWord.count <= Self.maxTriggerWordLength else { return false }

        // 获取当前触发词
        var currentWords = triggerWords

        // 检查重复（英文不区分大小写）
        let isDuplicate = currentWords.contains { existingWord in
            if existingWord.allSatisfy({ $0.isASCII }) && trimmedWord.allSatisfy({ $0.isASCII }) {
                return existingWord.lowercased() == trimmedWord.lowercased()
            }
            return existingWord == trimmedWord
        }

        guard !isDuplicate else { return false }

        // 添加新触发词
        currentWords.append(trimmedWord)
        userDefaults.set(currentWords, forKey: Keys.triggerWords)
        notifyCallbacks()
        return true
    }

    @discardableResult
    public func removeTriggerWord(_ word: String) -> Bool {
        var currentWords = triggerWords

        // 查找要删除的触发词
        guard let index = currentWords.firstIndex(of: word) else { return false }

        // 不能删除最后一个触发词
        guard currentWords.count > 1 else { return false }

        // 删除触发词
        currentWords.remove(at: index)
        userDefaults.set(currentWords, forKey: Keys.triggerWords)
        notifyCallbacks()
        return true
    }

    public func resetToDefault() {
        userDefaults.removeObject(forKey: Keys.enabled)
        userDefaults.removeObject(forKey: Keys.triggerWords)
        notifyCallbacks()
    }

    public func onSettingsChanged(_ callback: @escaping () -> Void) -> Cancellable {
        let id = UUID()
        callbacks[id] = callback
        return SettingsCancellable { [weak self] in
            self?.callbacks.removeValue(forKey: id)
        }
    }

    private func notifyCallbacks() {
        for callback in callbacks.values {
            callback()
        }
    }
}

// MARK: - SettingsCancellable

public class SettingsCancellable: Cancellable {
    private var onCancel: (() -> Void)?

    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }
}
