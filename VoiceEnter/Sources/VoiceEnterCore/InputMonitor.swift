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

    /// 防抖延迟（秒）
    var debounceDelay: TimeInterval = 0.3

    private var debounceWorkItem: DispatchWorkItem?

    init(keySimulator: KeySimulatorProtocol, settingsManager: SettingsManagerProtocol) {
        self.keySimulator = keySimulator
        self.settingsManager = settingsManager
        self.detector = TriggerWordDetector(triggerWords: settingsManager.triggerWords)
    }

    /// 开始监听
    func startMonitoring() {
        isMonitoring = true
        // 更新检测器的触发词
        detector.updateTriggerWords(settingsManager.triggerWords)
    }

    /// 停止监听
    func stopMonitoring() {
        isMonitoring = false
        // 取消任何待处理的防抖任务
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    /// 处理文本输入
    func handleTextInput(_ text: String) {
        // 取消之前的防抖任务
        debounceWorkItem?.cancel()

        // 如果未启动监听或功能关闭，直接返回
        guard isMonitoring, settingsManager.isEnabled else { return }

        // 更新检测器使用最新的触发词
        detector.updateTriggerWords(settingsManager.triggerWords)

        // 创建新的防抖任务
        let workItem = DispatchWorkItem { [weak self] in
            self?.processInput(text)
        }
        debounceWorkItem = workItem

        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    private func processInput(_ text: String) {
        // 检测触发词
        guard let result = detector.detect(in: text) else { return }

        // 计算需要删除的字符数（包括触发词和尾部空白）
        let originalText = text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingWhitespaceCount = originalText.count - trimmedText.count
        let deleteCount = result.triggerWord.count + trailingWhitespaceCount

        // 执行删除并回车
        _ = keySimulator.deleteThenEnter(deleteCount: deleteCount)

        // 调用回调
        onTrigger?(result.triggerWord)
    }
}
