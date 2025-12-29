import Foundation
import AppKit
import AVFoundation

// MARK: - KittyTerminalMonitor

/// Kitty 终端监听器 - 通过 kitty 远程控制 API 监听终端文本变化
public class KittyTerminalMonitor {
    private let keySimulator: KeySimulator
    private let settingsManager: SettingsManager
    private var detector: TriggerWordDetector
    
    /// 轮询间隔（秒）
    public var pollingInterval: TimeInterval = 0.15
    
    /// 防抖延迟（秒）
    public var debounceDelay: TimeInterval = 0.6
    
    private var pollingTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastScreenText: String = ""
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
        
        // 检查 kitty 是否支持远程控制
        guard checkKittyRemoteControl() else {
            voiceLog("[KittyMonitor] kitty 远程控制不可用，请确保 allow_remote_control 已启用")
            return false
        }
        
        // 启动轮询
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollKittyScreen()
        }
        
        isMonitoring = true
        onStatusChange?(true)
        
        detector.updateTriggerWords(settingsManager.triggerWords)
        
        voiceLog("[KittyMonitor] 开始监听 kitty 终端，触发词: \(settingsManager.triggerWords)")
        return true
    }
    
    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        pollingTimer?.invalidate()
        pollingTimer = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lastScreenText = ""
        lastInputLine = ""
        isMonitoring = false
        onStatusChange?(false)
        
        voiceLog("[KittyMonitor] 停止监听")
    }
    
    /// 检查辅助功能权限（保持接口兼容）
    public func checkAccessibilityPermission() -> Bool {
        // KittyTerminalMonitor 不需要辅助功能权限
        // 但需要 kitty 远程控制权限
        return checkKittyRemoteControl()
    }
    
    /// 请求辅助功能权限（保持接口兼容）
    public func requestAccessibilityPermission() {
        // 显示提示信息
        voiceLog("[KittyMonitor] 请确保 kitty.conf 中设置了 allow_remote_control yes")
    }
    
    // MARK: - Private
    
    private func checkKittyRemoteControl() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["kitty", "@", "ls"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            voiceLog("[KittyMonitor] 无法执行 kitty 命令: \(error)")
            return false
        }
    }
    
    private var pollCount = 0
    
    private func pollKittyScreen() {
        pollCount += 1

        guard settingsManager.isEnabled else { return }

        // 获取当前屏幕文本
        guard let screenText = getKittyScreenText() else {
            if pollCount % 50 == 0 {
                voiceLog("[KittyMonitor] 心跳 #\(pollCount), 无法获取屏幕文本")
            }
            return
        }

        // 文本没变化，跳过
        guard screenText != lastScreenText else { return }
        lastScreenText = screenText

        // 提取用户输入区域
        guard let inputLine = extractUserInputLine(from: screenText) else {
            return
        }

        // 如果输入行没变化，跳过
        guard inputLine != lastInputLine else { return }

        voiceLog("[KittyMonitor] 输入行变化: '\(lastInputLine)' -> '\(inputLine)'")
        lastInputLine = inputLine

        // 防抖处理
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkTrigger(text: inputLine)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    /// Claude Code 状态行的关键词（这些行不是用户输入）
    private static let claudeStatusKeywords: [String] = [
        "esc to interrupt",     // 处理中的状态提示
        "Perambulating",        // 思考动画
        "Churning",             // 思考动画
        "Thinking",             // 思考动画
        "Processing",           // 处理动画
        "Interrupted",          // 中断状态
        "What should Claude",   // 中断后的提示
        "· Perambulating",
        "· Churning",
        "· Thinking",
        "✻", "✽", "✶", "✳", "✢", "·",  // 旋转动画符号
        "[Image #",             // 图片标记
    ]

    /// 检查是否是 Claude Code 状态行（不是用户输入）
    private func isClaudeStatusLine(_ line: String) -> Bool {
        for keyword in Self.claudeStatusKeywords {
            if line.contains(keyword) {
                return true
            }
        }
        return false
    }

    /// Claude 响应开始的标记（遇到这些标记就停止收集用户输入）
    private static let claudeResponseMarkers: [String] = [
        "⏺",                    // Claude 响应开始标记
        "⎿",                    // Claude Code 的缩进符号
    ]

    /// 检查是否是 Claude 响应行的开始
    private func isClaudeResponseStart(_ line: String) -> Bool {
        for marker in Self.claudeResponseMarkers {
            if line.contains(marker) {
                return true
            }
        }
        return false
    }

    /// 从屏幕文本中提取用户输入行
    /// 支持多种模式：Claude Code 的 "> " 提示符、shell 的 "$ " 或 "% " 提示符等
    private func extractUserInputLine(from screenText: String) -> String? {
        let lines = screenText.components(separatedBy: .newlines)

        // 模式1: Claude Code 输入区域
        // 结构: 分隔线 -> "> " 行 -> (可能的多行输入) -> 分隔线 或 Claude 响应
        var foundSeparator = false
        var inputLines: [String] = []
        var afterPrompt = false

        for line in lines {
            let isSeparator = line.contains("────")

            if isSeparator {
                if afterPrompt {
                    // 找到输入区域结束的分隔线
                    break
                }
                foundSeparator = true
                continue
            }

            // 如果遇到 Claude 响应开始标记，停止收集
            if afterPrompt && isClaudeResponseStart(line) {
                break
            }

            // 查找 "> " 开头的行
            if foundSeparator && (line.hasPrefix("> ") || line.hasPrefix(">")) {
                afterPrompt = true
                // 提取 > 后面的内容
                var content = line
                if line.hasPrefix("> ") {
                    content = String(line.dropFirst(2))
                } else if line.hasPrefix(">") {
                    content = String(line.dropFirst(1))
                }
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                // 检查是否是状态行或 Claude 响应
                if !trimmed.isEmpty && !isClaudeStatusLine(trimmed) && !isClaudeResponseStart(trimmed) {
                    inputLines.append(trimmed)
                }
            } else if afterPrompt && !isSeparator {
                // 收集多行输入
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // 检查是否是状态行或 Claude 响应
                if !trimmed.isEmpty && !isClaudeStatusLine(trimmed) && !isClaudeResponseStart(trimmed) {
                    inputLines.append(trimmed)
                }
            }
        }

        // 如果找到了 Claude Code 输入内容，返回
        if !inputLines.isEmpty {
            return inputLines.joined(separator: " ")
        }

        // 模式2: 普通 shell 提示符 - 查找 shell 提示符行
        // 只在行首或空格后查找 $ 或 %
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // 跳过状态栏、分隔线和代码行
            if line.contains("────") || line.contains("INSERT") || line.contains("bypass") {
                continue
            }
            // 跳过代码行（包含常见代码关键字）
            if line.contains("let ") || line.contains("var ") || line.contains("func ") ||
               line.contains("if ") || line.contains("for ") || line.contains("return ") ||
               line.contains("guard ") || line.contains("else") || line.contains("//") ||
               line.contains("{") || line.contains("}") {
                continue
            }

            // 检测 shell 提示符（在行首或空格后）
            // 格式: "user@host $ command" 或 "$ command" 或 "% command"
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
    
    private func getKittyScreenText() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["kitty", "@", "get-text"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    /// 需要去除的尾部标点符号
    private static let trailingPunctuation: Set<Character> = [
        "。", ".", "！", "!", "？", "?", "，", ",", "；", ";", "：", ":",
        "、", "…", "~", "～"
    ]
    
    private func checkTrigger(text: String) {
        voiceLog("[KittyMonitor] 检查触发词，文本: '\(text)'")
        
        detector.updateTriggerWords(settingsManager.triggerWords)
        
        guard let result = detector.detect(in: text) else {
            voiceLog("[KittyMonitor] 未检测到触发词")
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
        
        voiceLog("[KittyMonitor] ✅ 检测到触发词 '\(result.triggerWord)'，删除 \(deleteCount) 个字符后回车")

        // 播放触发音效
        playTriggerSound()

        DispatchQueue.main.async { [weak self] in
            _ = self?.keySimulator.deleteThenEnter(deleteCount: deleteCount)
            self?.lastInputLine = ""
            self?.onTrigger?(result.triggerWord)
        }
    }

    /// 播放触发音效
    private func playTriggerSound() {
        let sound = settingsManager.triggerSound
        guard let soundName = sound.systemName else {
            voiceLog("[KittyMonitor] 音效已关闭")
            return
        }

        if let nsSound = NSSound(named: soundName) {
            nsSound.play()
            voiceLog("[KittyMonitor] 播放触发音效: \(soundName)")
        } else {
            NSSound.beep()
            voiceLog("[KittyMonitor] 播放系统提示音（\(soundName) 不可用）")
        }
    }
}
