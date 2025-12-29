import Foundation
import AppKit

// MARK: - UniversalInputMonitor

/// 通用输入监听器 - 同时使用多种监听方式，覆盖不同场景
/// - TextMonitor: 使用 Accessibility API，用于普通应用（Notes, Safari, 浏览器等）
/// - KittyTerminalMonitor: 使用 kitty 远程控制 API，用于 kitty 终端
public class UniversalInputMonitor {
    private let textMonitor: TextMonitor
    private let kittyMonitor: KittyTerminalMonitor
    private let settingsManager: SettingsManager

    /// 触发回调
    public var onTrigger: ((String) -> Void)? {
        didSet {
            textMonitor.onTrigger = onTrigger
            kittyMonitor.onTrigger = onTrigger
        }
    }

    /// 状态变化回调
    public var onStatusChange: ((Bool) -> Void)?

    /// 是否正在监听
    public private(set) var isMonitoring: Bool = false

    public init() {
        self.settingsManager = SettingsManager()
        self.textMonitor = TextMonitor()
        self.kittyMonitor = KittyTerminalMonitor()
    }

    /// 开始监听
    public func startMonitoring() -> Bool {
        guard !isMonitoring else { return true }

        voiceLog("[UniversalMonitor] 启动通用输入监听器")

        // 启动 TextMonitor（Accessibility API）
        let textStarted = textMonitor.startMonitoring()
        if textStarted {
            voiceLog("[UniversalMonitor] TextMonitor 启动成功")
        } else {
            voiceLog("[UniversalMonitor] TextMonitor 启动失败（可能缺少辅助功能权限）")
        }

        // 启动 KittyTerminalMonitor
        let kittyStarted = kittyMonitor.startMonitoring()
        if kittyStarted {
            voiceLog("[UniversalMonitor] KittyTerminalMonitor 启动成功")
        } else {
            voiceLog("[UniversalMonitor] KittyTerminalMonitor 启动失败（kitty 可能未运行或远程控制未启用）")
        }

        // 只要有一个成功就算成功
        isMonitoring = textStarted || kittyStarted

        if isMonitoring {
            voiceLog("[UniversalMonitor] 通用输入监听器已启动")
            onStatusChange?(true)
        } else {
            voiceLog("[UniversalMonitor] 通用输入监听器启动失败")
        }

        return isMonitoring
    }

    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }

        textMonitor.stopMonitoring()
        kittyMonitor.stopMonitoring()

        isMonitoring = false
        onStatusChange?(false)

        voiceLog("[UniversalMonitor] 通用输入监听器已停止")
    }

    /// 检查辅助功能权限
    public func checkAccessibilityPermission() -> Bool {
        // TextMonitor 需要辅助功能权限
        // KittyMonitor 需要 kitty 远程控制权限
        // 返回 TextMonitor 的权限状态（因为它是更通用的方案）
        return textMonitor.checkAccessibilityPermission()
    }

    /// 请求辅助功能权限
    public func requestAccessibilityPermission() {
        textMonitor.requestAccessibilityPermission()
    }
}
