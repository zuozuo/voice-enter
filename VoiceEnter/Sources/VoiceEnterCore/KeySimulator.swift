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
        // TODO: 实现
        fatalError("Not implemented")
    }

    /// 删除指定数量的字符
    func deleteCharacters(count: Int) -> Bool {
        // TODO: 实现
        fatalError("Not implemented")
    }

    /// 删除字符后按回车
    func deleteThenEnter(deleteCount: Int) -> Bool {
        // TODO: 实现
        fatalError("Not implemented")
    }
}

// MARK: - CGEventPoster

/// 真实的事件发送器，使用 CGEvent
class CGEventPoster: EventPosterProtocol {
    func postKeyDown(keyCode: CGKeyCode) -> Bool {
        // TODO: 实现
        fatalError("Not implemented")
    }

    func postKeyUp(keyCode: CGKeyCode) -> Bool {
        // TODO: 实现
        fatalError("Not implemented")
    }
}
