import Foundation
import CoreGraphics

// MARK: - Protocols

/// 事件发送器协议，用于模拟键盘事件
protocol EventPosterProtocol {
    func postKeyDown(keyCode: CGKeyCode) -> Bool
    func postKeyUp(keyCode: CGKeyCode) -> Bool
}

/// 按键模拟器协议
protocol KeySimulatorProtocol {
    func simulateEnter() -> Bool
    func deleteCharacters(count: Int) -> Bool
    func deleteThenEnter(deleteCount: Int) -> Bool
}

/// 设置管理器协议
protocol SettingsManagerProtocol {
    var isEnabled: Bool { get set }
    var triggerWords: [String] { get }

    func addTriggerWord(_ word: String) -> Bool
    func removeTriggerWord(_ word: String) -> Bool
    func resetToDefault()
    func onSettingsChanged(_ callback: @escaping () -> Void) -> Cancellable
}

/// 可取消协议
protocol Cancellable {
    func cancel()
}
