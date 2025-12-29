import Foundation
import CoreGraphics
import Carbon

// MARK: - SystemInputMonitor

/// 系统输入监听器 - 使用 CGEventTap 监听全局键盘输入
public class SystemInputMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentText: String = ""

    private let keySimulator: KeySimulator
    private let settingsManager: SettingsManager
    private var detector: TriggerWordDetector

    /// 防抖延迟（秒）
    public var debounceDelay: TimeInterval = 0.3
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
            print("VoiceEnter: 需要辅助功能权限")
            return false
        }

        // 创建事件回调
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // 使用闭包包装 self
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
                let monitor = Unmanaged<SystemInputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            print("VoiceEnter: 无法创建事件监听器")
            return false
        }

        eventTap = tap

        // 创建 RunLoop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        // 添加到主 RunLoop
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        // 启用 tap
        CGEvent.tapEnable(tap: tap, enable: true)

        isMonitoring = true
        onStatusChange?(true)

        // 更新触发词
        detector.updateTriggerWords(settingsManager.triggerWords)

        print("VoiceEnter: 开始监听输入")
        return true
    }

    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }

        // 取消防抖任务
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        // 禁用并移除 tap
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

        print("VoiceEnter: 停止监听输入")
    }

    /// 检查辅助功能权限
    public func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 请求辅助功能权限
    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 检查功能是否启用
        guard settingsManager.isEnabled else {
            return Unmanaged.passRetained(event)
        }

        // 处理键盘事件
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // 回车键 - 重置当前文本
            if keyCode == 36 {
                currentText = ""
                debounceWorkItem?.cancel()
                return Unmanaged.passRetained(event)
            }

            // 删除键 - 删除最后一个字符
            if keyCode == 51 {
                if !currentText.isEmpty {
                    currentText.removeLast()
                }
                return Unmanaged.passRetained(event)
            }

            // 获取输入的字符
            var unicodeString = [UniChar](repeating: 0, count: 4)
            var length: Int = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &unicodeString)

            if length > 0 {
                let chars = unicodeString.prefix(length).map { Character(UnicodeScalar($0)!) }
                let inputString = String(chars)
                currentText += inputString

                // 防抖处理
                debounceWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.checkTrigger()
                }
                debounceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func checkTrigger() {
        // 更新触发词
        detector.updateTriggerWords(settingsManager.triggerWords)

        // 检测触发词
        guard let result = detector.detect(in: currentText) else { return }

        // 计算需要删除的字符数
        let deleteCount = result.triggerWord.count

        print("VoiceEnter: 检测到触发词 '\(result.triggerWord)'，删除 \(deleteCount) 个字符后按回车")

        // 执行删除并回车
        DispatchQueue.main.async { [weak self] in
            _ = self?.keySimulator.deleteThenEnter(deleteCount: deleteCount)
            self?.currentText = ""
            self?.onTrigger?(result.triggerWord)
        }
    }
}
