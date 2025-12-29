import Foundation
import AppKit

// MARK: - TerminalAppMonitor

/// macOS 原生 Terminal.app 监听器 - 通过 AppleScript 获取终端内容
public class TerminalAppMonitor {
    private let keySimulator: KeySimulator
    private let settingsManager: SettingsManager
    private var detector: TriggerWordDetector

    /// 轮询间隔（秒）
    public var pollingInterval: TimeInterval = 0.2

    /// 防抖延迟（秒）
    public var debounceDelay: TimeInterval = 0.6

    private var pollingTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastContent: String = ""
    private var lastInputLine: String = ""

    /// 触发回调
    public var onTrigger: ((String) -> Void)?

    /// 状态变化回调
    public var onStatusChange: ((Bool) -> Void)?

    /// 是否正在监听
    public private(set) var isMonitoring: Bool = false

    public init() {
        self.settingsManager = SettingsManager()
        self.keySimulator = KeySimulator(eventPoster: CGEventPoster())
        self.detector = TriggerWordDetector(triggerWords: settingsManager.triggerWords)
    }

    /// 开始监听
    public func startMonitoring() -> Bool {
        guard !isMonitoring else { return true }

        // 检查 Terminal.app 是否在运行
        guard isTerminalRunning() else {
            voiceLog("[TerminalMonitor] Terminal.app 未运行")
            return false
        }

        // 启动轮询
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollTerminalContent()
        }

        isMonitoring = true
        onStatusChange?(true)

        detector.updateTriggerWords(settingsManager.triggerWords)

        voiceLog("[TerminalMonitor] 开始监听 Terminal.app，触发词: \(settingsManager.triggerWords)")
        return true
    }

    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }

        pollingTimer?.invalidate()
        pollingTimer = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lastContent = ""
        lastInputLine = ""
        isMonitoring = false
        onStatusChange?(false)

        voiceLog("[TerminalMonitor] 停止监听")
    }

    /// 检查辅助功能权限（保持接口兼容）
    public func checkAccessibilityPermission() -> Bool {
        // TerminalAppMonitor 使用 AppleScript，不需要辅助功能权限
        // 但需要 Terminal.app 在运行
        return isTerminalRunning()
    }

    /// 请求辅助功能权限（保持接口兼容）
    public func requestAccessibilityPermission() {
        voiceLog("[TerminalMonitor] 请确保 Terminal.app 正在运行")
    }

    // MARK: - Private

    private func isTerminalRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.Terminal" }
    }

    private func isTerminalFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return frontApp.bundleIdentifier == "com.apple.Terminal"
    }

    private var pollCount = 0

    private func pollTerminalContent() {
        pollCount += 1

        guard settingsManager.isEnabled else { return }

        // 检查触发范围：TerminalAppMonitor 在 terminalsOnly 和 allApps 模式下工作
        guard settingsManager.triggerScope != .kittyOnly else { return }

        // 只有当 Terminal 是前台应用时才监听
        guard isTerminalFrontmost() else {
            return
        }

        // 获取 Terminal 内容
        guard let content = getTerminalContent() else {
            if pollCount % 50 == 0 {
                voiceLog("[TerminalMonitor] 心跳 #\(pollCount), 无法获取 Terminal 内容")
            }
            return
        }

        // 内容没变化，跳过
        guard content != lastContent else { return }
        lastContent = content

        // 提取用户输入行
        guard let inputLine = extractUserInputLine(from: content) else {
            return
        }

        // 如果输入行没变化，跳过
        guard inputLine != lastInputLine else { return }

        voiceLog("[TerminalMonitor] 输入行变化: '\(lastInputLine)' -> '\(inputLine)'")
        lastInputLine = inputLine

        // 防抖处理
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkTrigger(text: inputLine)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    private func getTerminalContent() -> String? {
        let script = """
        tell application "Terminal"
            if (count of windows) > 0 then
                return contents of front window
            else
                return ""
            end if
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return result.stringValue
            }
        }
        return nil
    }

    /// 从终端内容中提取用户输入行
    /// 查找最后一个 shell 提示符后的内容
    private func extractUserInputLine(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)

        // 从后往前找最后一个非空行（当前输入行）
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // 跳过命令输出行（不包含提示符的行）
            // 查找 shell 提示符：$ % > ➜ 等
            // zsh 的提示符通常是 "➜" 或自定义的
            // bash 的提示符通常是 "$"

            // 检测 zsh 风格提示符 (➜)
            if let range = line.range(of: "➜") {
                let afterPrompt = line[range.upperBound...]
                // 可能有路径等，查找最后一个空格后的内容
                if let lastSpace = afterPrompt.lastIndex(of: " ") {
                    let input = String(afterPrompt[afterPrompt.index(after: lastSpace)...])
                    if !input.isEmpty {
                        return input.trimmingCharacters(in: .whitespaces)
                    }
                }
                // 如果没有空格，返回 ➜ 后面的全部内容
                let input = String(afterPrompt).trimmingCharacters(in: .whitespaces)
                if !input.isEmpty {
                    return input
                }
            }

            // 检测 bash 风格提示符 ($ 或 %)
            if let range = line.range(of: "\\s\\$\\s|^\\$\\s", options: .regularExpression) {
                let afterDollar = line[range.upperBound...]
                let input = afterDollar.trimmingCharacters(in: .whitespaces)
                if !input.isEmpty {
                    return input
                }
            }

            if let range = line.range(of: "\\s%\\s|^%\\s", options: .regularExpression) {
                let afterPercent = line[range.upperBound...]
                let input = afterPercent.trimmingCharacters(in: .whitespaces)
                if !input.isEmpty {
                    return input
                }
            }
        }

        return nil
    }

    /// 需要去除的尾部标点符号
    private static let trailingPunctuation: Set<Character> = [
        "。", ".", "！", "!", "？", "?", "，", ",", "；", ";", "：", ":",
        "、", "…", "~", "～"
    ]

    private func checkTrigger(text: String) {
        voiceLog("[TerminalMonitor] 检查触发词，文本: '\(text)'")

        detector.updateTriggerWords(settingsManager.triggerWords)

        guard let result = detector.detect(in: text) else {
            voiceLog("[TerminalMonitor] 未检测到触发词")
            return
        }

        // 计算需要删除的字符数（包括尾部标点）
        var trailingCount = 0
        var tempText = text
        while let last = tempText.last,
              last.isWhitespace || last.isNewline || Self.trailingPunctuation.contains(last) {
            tempText.removeLast()
            trailingCount += 1
        }
        let deleteCount = result.triggerWord.count + trailingCount

        voiceLog("[TerminalMonitor] ✅ 检测到触发词 '\(result.triggerWord)'，删除 \(deleteCount) 个字符后回车")

        DispatchQueue.main.async { [weak self] in
            _ = self?.keySimulator.deleteThenEnter(deleteCount: deleteCount)
            self?.lastInputLine = ""
            self?.onTrigger?(result.triggerWord)
        }
    }
}
