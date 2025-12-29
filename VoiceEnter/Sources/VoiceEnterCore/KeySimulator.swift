import Foundation
import CoreGraphics

// MARK: - KeySimulator

/// 按键模拟器 - 模拟键盘按键事件
class KeySimulator: KeySimulatorProtocol {
    static let enterKeyCode: CGKeyCode = 36
    static let deleteKeyCode: CGKeyCode = 51

    private let eventPoster: EventPosterProtocol

    init(eventPoster: EventPosterProtocol) {
        self.eventPoster = eventPoster
    }

    /// 模拟按下回车键
    func simulateEnter() -> Bool {
        // 先按下，再释放
        guard eventPoster.postKeyDown(keyCode: Self.enterKeyCode) else {
            return false
        }
        guard eventPoster.postKeyUp(keyCode: Self.enterKeyCode) else {
            return false
        }
        return true
    }

    /// 删除指定数量的字符
    func deleteCharacters(count: Int) -> Bool {
        // 负数无效
        guard count >= 0 else { return false }

        // 0 个字符直接成功
        guard count > 0 else { return true }

        // 按 count 次 delete 键
        for _ in 0..<count {
            guard eventPoster.postKeyDown(keyCode: Self.deleteKeyCode) else {
                return false
            }
            guard eventPoster.postKeyUp(keyCode: Self.deleteKeyCode) else {
                return false
            }
        }
        return true
    }

    /// 删除字符后按回车
    func deleteThenEnter(deleteCount: Int) -> Bool {
        // 先删除
        guard deleteCharacters(count: deleteCount) else {
            return false
        }
        // 再回车
        return simulateEnter()
    }
}

// MARK: - CGEventPoster

/// 真实的事件发送器，使用 CGEvent
class CGEventPoster: EventPosterProtocol {
    func postKeyDown(keyCode: CGKeyCode) -> Bool {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    func postKeyUp(keyCode: CGKeyCode) -> Bool {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }
}
