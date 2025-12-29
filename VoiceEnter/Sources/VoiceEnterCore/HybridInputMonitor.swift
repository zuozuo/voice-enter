import Foundation
import CoreGraphics
import Carbon
import AppKit

// MARK: - HybridInputMonitor

/// 混合输入监听器 - 同时监听键盘事件和输入法文本提交
public class HybridInputMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentText: String = ""

    private let keySimulator: KeySimulator
    private let settingsManager: SettingsManager
    private var detector: TriggerWordDetector

    /// 防抖延迟（秒）
    public var debounceDelay: TimeInterval = 0.5
    private var debounceWorkItem: DispatchWorkItem?

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

        // 检查辅助功能权限
        guard checkAccessibilityPermission() else {
            voiceLog("[HybridMonitor] 需要辅助功能权限")
            return false
        }

        // 监听所有键盘相关事件（包括输入法提交）
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let monitor = Unmanaged<HybridInputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            voiceLog("[HybridMonitor] 无法创建事件监听器")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isMonitoring = true
        onStatusChange?(true)

        detector.updateTriggerWords(settingsManager.triggerWords)

        voiceLog("[HybridMonitor] 开始监听，触发词: \(settingsManager.triggerWords)")
        return true
    }

    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }

        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        currentText = ""
        isMonitoring = false
        onStatusChange?(false)

        voiceLog("[HybridMonitor] 停止监听")
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

    private var lastLogTime: Date = Date()
    private var eventCount = 0

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard settingsManager.isEnabled else {
            return Unmanaged.passRetained(event)
        }

        eventCount += 1

        // keyDown 事件
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // 回车键 - 重置
            if keyCode == 36 {
                voiceLog("[HybridMonitor] Enter键，重置缓冲区: '\(currentText)'")
                currentText = ""
                debounceWorkItem?.cancel()
                return Unmanaged.passRetained(event)
            }

            // 删除键
            if keyCode == 51 {
                if !currentText.isEmpty {
                    currentText.removeLast()
                }
                return Unmanaged.passRetained(event)
            }

            // 获取输入的字符（包括输入法提交的文本）
            var unicodeString = [UniChar](repeating: 0, count: 64)  // 增大缓冲区以容纳输入法文本
            var length: Int = 0
            event.keyboardGetUnicodeString(maxStringLength: 64, actualStringLength: &length, unicodeString: &unicodeString)

            if length > 0 {
                let chars = unicodeString.prefix(length).compactMap { UnicodeScalar($0).map { Character($0) } }
                let inputString = String(chars)

                // 过滤掉控制字符
                let filteredInput = inputString.filter { !$0.isNewline && $0.asciiValue.map { $0 >= 32 } ?? true }

                if !filteredInput.isEmpty {
                    currentText += filteredInput
                    voiceLog("[HybridMonitor] 输入: '\(filteredInput)' | 缓冲区: '\(currentText)'")

                    // 防抖处理
                    debounceWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak self] in
                        self?.checkTrigger()
                    }
                    debounceWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// 需要去除的尾部标点符号
    private static let trailingPunctuation: Set<Character> = [
        "。", ".", "！", "!", "？", "?", "，", ",", "；", ";", "：", ":",
        "、", "…", "~", "～"
    ]

    private func checkTrigger() {
        voiceLog("[HybridMonitor] 检查触发词，缓冲区: '\(currentText)'")

        detector.updateTriggerWords(settingsManager.triggerWords)

        guard let result = detector.detect(in: currentText) else {
            voiceLog("[HybridMonitor] 未检测到触发词")
            return
        }

        // 计算需要删除的字符数（包括尾部标点）
        var trailingCount = 0
        var tempText = currentText
        while let last = tempText.last,
              last.isWhitespace || last.isNewline || Self.trailingPunctuation.contains(last) {
            tempText.removeLast()
            trailingCount += 1
        }
        let deleteCount = result.triggerWord.count + trailingCount

        voiceLog("[HybridMonitor] ✅ 检测到触发词 '\(result.triggerWord)'，删除 \(deleteCount) 个字符后回车")

        DispatchQueue.main.async { [weak self] in
            _ = self?.keySimulator.deleteThenEnter(deleteCount: deleteCount)
            self?.currentText = ""
            self?.onTrigger?(result.triggerWord)
        }
    }
}
