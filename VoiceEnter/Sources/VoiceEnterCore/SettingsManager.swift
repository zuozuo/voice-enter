import Foundation

// MARK: - SettingsManager

/// 设置管理器 - 管理应用设置的持久化
class SettingsManager: SettingsManagerProtocol {
    private let userDefaults: UserDefaults
    private var callbacks: [() -> Void] = []

    private enum Keys {
        static let enabled = "voiceenter.enabled"
        static let triggerWords = "voiceenter.triggerWords"
    }

    private static let defaultTriggerWords = ["发送", "Go"]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get {
            // TODO: 实现
            fatalError("Not implemented")
        }
        set {
            // TODO: 实现
            fatalError("Not implemented")
        }
    }

    var triggerWords: [String] {
        // TODO: 实现
        fatalError("Not implemented")
    }

    func addTriggerWord(_ word: String) -> Bool {
        // TODO: 实现
        fatalError("Not implemented")
    }

    func removeTriggerWord(_ word: String) -> Bool {
        // TODO: 实现
        fatalError("Not implemented")
    }

    func resetToDefault() {
        // TODO: 实现
        fatalError("Not implemented")
    }

    func onSettingsChanged(_ callback: @escaping () -> Void) -> Cancellable {
        // TODO: 实现
        fatalError("Not implemented")
    }
}

// MARK: - SettingsCancellable

class SettingsCancellable: Cancellable {
    private var callback: (() -> Void)?
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
