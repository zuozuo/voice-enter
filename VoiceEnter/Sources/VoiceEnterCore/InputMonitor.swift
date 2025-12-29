import Foundation

// MARK: - InputMonitor

/// 输入监听器 - 监听系统输入并触发回车
class InputMonitor {
    private let keySimulator: KeySimulatorProtocol
    private let settingsManager: SettingsManagerProtocol
    private var detector: TriggerWordDetector

    private(set) var isMonitoring = false

    /// 触发回调
    var onTrigger: ((String) -> Void)?

    /// 防抖延迟（毫秒）
    var debounceDelay: TimeInterval = 0.3

    private var debounceWorkItem: DispatchWorkItem?

    init(keySimulator: KeySimulatorProtocol, settingsManager: SettingsManagerProtocol) {
        self.keySimulator = keySimulator
        self.settingsManager = settingsManager
        self.detector = TriggerWordDetector(triggerWords: settingsManager.triggerWords)
    }

    /// 开始监听
    func startMonitoring() {
        // TODO: 实现
        fatalError("Not implemented")
    }

    /// 停止监听
    func stopMonitoring() {
        // TODO: 实现
        fatalError("Not implemented")
    }

    /// 处理文本输入
    func handleTextInput(_ text: String) {
        // TODO: 实现
        fatalError("Not implemented")
    }
}
