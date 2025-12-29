import Foundation

// MARK: - TriggerWordDetector

/// 触发词检测结果
public struct TriggerDetectionResult {
    public let triggerWord: String
    public let contentWithoutTrigger: String

    public init(triggerWord: String, contentWithoutTrigger: String) {
        self.triggerWord = triggerWord
        self.contentWithoutTrigger = contentWithoutTrigger
    }
}

/// 触发词检测器 - 检测输入文本是否以触发词结尾
public class TriggerWordDetector {
    private var triggerWords: [String]

    public init(triggerWords: [String]) {
        self.triggerWords = triggerWords
    }

    /// 检测输入文本是否以触发词结尾
    /// - Parameter text: 输入文本
    /// - Returns: 如果检测到触发词，返回检测结果；否则返回 nil
    public func detect(in text: String) -> TriggerDetectionResult? {
        // 空输入不触发
        guard !text.isEmpty else { return nil }

        // 只去除尾部空白字符（保留开头空白）
        var trimmedText = text
        while let last = trimmedText.last, last.isWhitespace || last.isNewline {
            trimmedText.removeLast()
        }

        // 空触发词列表不触发
        guard !triggerWords.isEmpty else { return nil }

        // 检查每个触发词
        for triggerWord in triggerWords {
            // 对英文触发词进行大小写不敏感匹配
            let isEnglishTrigger = triggerWord.allSatisfy { $0.isASCII }

            let matchedTrigger: String?
            if isEnglishTrigger {
                // 英文：不区分大小写
                if trimmedText.lowercased().hasSuffix(triggerWord.lowercased()) {
                    // 获取实际匹配的文本（保留原始大小写）
                    let startIndex = trimmedText.index(trimmedText.endIndex, offsetBy: -triggerWord.count)
                    matchedTrigger = String(trimmedText[startIndex...])
                } else {
                    matchedTrigger = nil
                }
            } else {
                // 非英文：精确匹配
                if trimmedText.hasSuffix(triggerWord) {
                    matchedTrigger = triggerWord
                } else {
                    matchedTrigger = nil
                }
            }

            if let matched = matchedTrigger {
                // 获取不包含触发词的内容
                let endIndex = trimmedText.index(trimmedText.endIndex, offsetBy: -matched.count)
                let contentWithoutTrigger = String(trimmedText[..<endIndex])

                // 如果内容为空或只有空白，不触发（避免误发空消息）
                let trimmedContent = contentWithoutTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedContent.isEmpty {
                    return nil
                }

                return TriggerDetectionResult(
                    triggerWord: matched,
                    contentWithoutTrigger: contentWithoutTrigger
                )
            }
        }

        return nil
    }

    /// 更新触发词列表
    public func updateTriggerWords(_ words: [String]) {
        self.triggerWords = words
    }
}
