import Foundation

// MARK: - TriggerWordDetector

/// 触发词检测结果
struct TriggerDetectionResult {
    let triggerWord: String
    let contentWithoutTrigger: String
}

/// 触发词检测器 - 检测输入文本是否以触发词结尾
class TriggerWordDetector {
    private var triggerWords: [String]

    init(triggerWords: [String]) {
        self.triggerWords = triggerWords
    }

    /// 检测输入文本是否以触发词结尾
    /// - Parameter text: 输入文本
    /// - Returns: 如果检测到触发词，返回检测结果；否则返回 nil
    func detect(in text: String) -> TriggerDetectionResult? {
        // TODO: 实现触发词检测逻辑
        fatalError("Not implemented")
    }

    /// 更新触发词列表
    func updateTriggerWords(_ words: [String]) {
        // TODO: 实现更新逻辑
        fatalError("Not implemented")
    }
}
