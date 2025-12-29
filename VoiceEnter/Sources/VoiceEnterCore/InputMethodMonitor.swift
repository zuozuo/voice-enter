import Foundation
import CoreGraphics
import Carbon
import AppKit

// MARK: - InputMethodMonitor

/// 输入法监听器 - 尝试通过多种方式捕获语音输入
public class InputMethodMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentText: String = ""
    
    private let keySimulator: KeySimulator
    private let settingsManager: SettingsManager
    private var detector: TriggerWordDetector
    
    /// 防抖延迟（秒）
    public var debounceDelay: TimeInterval = 0.8
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
        
        guard checkAccessibilityPermission() else {
            voiceLog("[InputMethodMonitor] 需要辅助功能权限")
            return false
        }
        
        // 监听所有可能的事件，包括 otherMouseDown 等系统事件
        // 关键：添加对 kCGEventKeyboardEventAutorepeat 和其他事件的监听
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
                let monitor = Unmanaged<InputMethodMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            voiceLog("[InputMethodMonitor] 无法创建事件监听器")
            return false
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // 同时启动剪贴板监控
        startClipboardMonitoring()
        
        isMonitoring = true
        onStatusChange?(true)
        
        detector.updateTriggerWords(settingsManager.triggerWords)
        
        voiceLog("[InputMethodMonitor] 开始监听，触发词: \(settingsManager.triggerWords)")
        return true
    }
    
    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        
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
        
        voiceLog("[InputMethodMonitor] 停止监听")
    }
    
    public func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Clipboard Monitoring
    
    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount: Int = 0
    private var lastClipboardContent: String = ""
    
    private func startClipboardMonitoring() {
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        lastClipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
        
        // 每 200ms 检查一次剪贴板变化
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkClipboardChange()
        }
    }
    
    private func checkClipboardChange() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else { return }
        
        lastClipboardChangeCount = currentCount
        
        guard let content = NSPasteboard.general.string(forType: .string),
              content != lastClipboardContent else { return }
        
        voiceLog("[InputMethodMonitor] 剪贴板变化: '\(content)'")
        lastClipboardContent = content
        
        // 检查是否包含触发词（某些语音输入可能通过剪贴板）
        // 这里只是探测性检查
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard settingsManager.isEnabled else {
            return Unmanaged.passRetained(event)
        }
        
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // 获取事件的额外信息
            let flags = event.flags
            let eventSource = event.getIntegerValueField(.eventSourceUserData)
            
            // 回车键 - 重置
            if keyCode == 36 {
                voiceLog("[InputMethodMonitor] Enter键，重置缓冲区: '\(currentText)'")
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
            
            // 获取 Unicode 字符串 - 使用更大的缓冲区
            var unicodeString = [UniChar](repeating: 0, count: 255)
            var length: Int = 0
            event.keyboardGetUnicodeString(maxStringLength: 255, actualStringLength: &length, unicodeString: &unicodeString)
            
            if length > 0 {
                let chars = unicodeString.prefix(length).compactMap { UnicodeScalar($0).map { Character($0) } }
                let inputString = String(chars)
                
                let filteredInput = inputString.filter { !$0.isNewline && $0.asciiValue.map { $0 >= 32 } ?? true }
                
                if !filteredInput.isEmpty {
                    currentText += filteredInput
                    
                    // 如果输入超过 1 个字符，可能是输入法批量提交
                    if filteredInput.count > 1 {
                        voiceLog("[InputMethodMonitor] 批量输入检测: '\(filteredInput)' (长度: \(filteredInput.count)) | 缓冲区: '\(currentText)'")
                    } else {
                        voiceLog("[InputMethodMonitor] 单字符输入: '\(filteredInput)' | 缓冲区: '\(currentText)'")
                    }
                    
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
    
    private static let trailingPunctuation: Set<Character> = [
        "。", ".", "！", "!", "？", "?", "，", ",", "；", ";", "：", ":",
        "、", "…", "~", "～"
    ]
    
    private func checkTrigger() {
        voiceLog("[InputMethodMonitor] 检查触发词，缓冲区: '\(currentText)'")
        
        detector.updateTriggerWords(settingsManager.triggerWords)
        
        guard let result = detector.detect(in: currentText) else {
            voiceLog("[InputMethodMonitor] 未检测到触发词")
            return
        }
        
        var trailingCount = 0
        var tempText = currentText
        while let last = tempText.last,
              last.isWhitespace || last.isNewline || Self.trailingPunctuation.contains(last) {
            tempText.removeLast()
            trailingCount += 1
        }
        let deleteCount = result.triggerWord.count + trailingCount
        
        voiceLog("[InputMethodMonitor] ✅ 检测到触发词 '\(result.triggerWord)'，删除 \(deleteCount) 个字符后回车")
        
        DispatchQueue.main.async { [weak self] in
            _ = self?.keySimulator.deleteThenEnter(deleteCount: deleteCount)
            self?.currentText = ""
            self?.onTrigger?(result.triggerWord)
        }
    }
}
