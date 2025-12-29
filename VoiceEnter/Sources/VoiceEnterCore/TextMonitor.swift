import Foundation
import ApplicationServices
import AppKit

// 简单的日志函数，写入文件
func voiceLog(_ message: String) {
    let logFile = "/tmp/voiceenter.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data, attributes: nil)
        }
    }
    print(message)  // 也打印到 stdout
}

// MARK: - TextMonitor

/// 文本监听器 - 使用 Accessibility API 监听文本输入（支持语音输入）
public class TextMonitor {
    private let keySimulator: KeySimulator
    private let settingsManager: SettingsManager
    private var detector: TriggerWordDetector

    /// 轮询间隔（秒）
    public var pollingInterval: TimeInterval = 0.2

    /// 防抖延迟（秒）
    public var debounceDelay: TimeInterval = 0.5

    private var pollingTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastText: String = ""

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
        voiceLog("[TextMonitor] startMonitoring() 被调用")
        guard !isMonitoring else {
            voiceLog("[TextMonitor] 已经在监听中")
            return true
        }

        // 检查辅助功能权限
        let hasPermission = checkAccessibilityPermission()
        voiceLog("[TextMonitor] 辅助功能权限: \(hasPermission)")
        guard hasPermission else {
            voiceLog("[TextMonitor] 需要辅助功能权限")
            return false
        }

        // 启动轮询定时器
        voiceLog("[TextMonitor] 启动轮询定时器，间隔: \(pollingInterval)s")
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollFocusedText()
        }

        isMonitoring = true
        onStatusChange?(true)

        // 更新触发词
        detector.updateTriggerWords(settingsManager.triggerWords)

        voiceLog("[TextMonitor] 开始监听文本输入，触发词: \(settingsManager.triggerWords)")
        return true
    }

    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }

        pollingTimer?.invalidate()
        pollingTimer = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lastText = ""
        isMonitoring = false
        onStatusChange?(false)

        print("[TextMonitor] 停止监听")
    }

    /// 检查辅助功能权限
    public func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 请求辅助功能权限
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private

    private var pollCount = 0

    private func pollFocusedText() {
        pollCount += 1
        if pollCount % 25 == 0 {  // 每5秒打印一次心跳
            voiceLog("[TextMonitor] 心跳 #\(pollCount), isEnabled=\(settingsManager.isEnabled), scope=\(settingsManager.triggerScope.displayName)")
        }

        guard settingsManager.isEnabled else { return }

        // 检查触发范围：TextMonitor 只在 allApps 模式下工作
        guard settingsManager.triggerScope == .allApps else { return }

        // 获取当前焦点元素的文本
        let (text, debugInfo) = getFocusedElementTextWithDebug()
        guard let text = text else {
            if pollCount % 25 == 0 {
                voiceLog("[TextMonitor] 无法获取焦点元素文本 - \(debugInfo)")
            }
            return
        }

        // 文本没有变化，跳过
        guard text != lastText else { return }

        voiceLog("[TextMonitor] 文本变化: '\(lastText)' -> '\(text)'")
        lastText = text

        // 防抖处理
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkTrigger(text: text)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    private func getFocusedElementText() -> String? {
        return getFocusedElementTextWithDebug().0
    }

    private func getFocusedElementTextWithDebug() -> (String?, String) {
        // 获取系统焦点元素
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return (nil, "无焦点元素, error=\(result.rawValue)")
        }

        let axElement = element as! AXUIElement

        // 获取元素角色和描述
        var roleValue: CFTypeRef?
        var role = "unknown"
        if AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue) == .success,
           let r = roleValue as? String {
            role = r
        }

        var descValue: CFTypeRef?
        var desc = ""
        if AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descValue) == .success,
           let d = descValue as? String {
            desc = d
        }

        // 尝试多种属性获取文本
        var value: CFTypeRef?

        // 1. 首先尝试 kAXValueAttribute（文本框）
        if AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value) == .success,
           let textValue = value as? String {
            return (textValue, "role=\(role)")
        }

        // 2. 尝试 kAXSelectedTextAttribute（选中的文本）
        if AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &value) == .success,
           let textValue = value as? String, !textValue.isEmpty {
            return (textValue, "selectedText, role=\(role)")
        }

        // 3. 尝试获取整个文档的文本（适用于某些编辑器）
        if AXUIElementCopyAttributeValue(axElement, "AXDocument" as CFString, &value) == .success,
           let docElement = value {
            if AXUIElementCopyAttributeValue(docElement as! AXUIElement, kAXValueAttribute as CFString, &value) == .success,
               let textValue = value as? String {
                return (textValue, "document, role=\(role)")
            }
        }

        return (nil, "role=\(role), desc=\(desc), 无 Value 属性")
    }

    /// 需要去除的尾部标点符号
    private static let trailingPunctuation: Set<Character> = [
        "。", ".", "！", "!", "？", "?", "，", ",", "；", ";", "：", ":",
        "、", "…", "~", "～"
    ]

    private func checkTrigger(text: String) {
        print("[TextMonitor] 检查触发词，文本: '\(text)'")

        // 更新触发词
        detector.updateTriggerWords(settingsManager.triggerWords)

        // 检测触发词
        guard let result = detector.detect(in: text) else {
            print("[TextMonitor] 未检测到触发词")
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

        print("[TextMonitor] 检测到触发词 '\(result.triggerWord)'，删除 \(deleteCount) 个字符后按回车")

        // 执行删除并回车
        DispatchQueue.main.async { [weak self] in
            _ = self?.keySimulator.deleteThenEnter(deleteCount: deleteCount)
            self?.lastText = ""
            self?.onTrigger?(result.triggerWord)
        }
    }
}
