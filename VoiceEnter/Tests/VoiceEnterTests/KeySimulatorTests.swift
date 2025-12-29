import XCTest
@testable import VoiceEnterCore

final class KeySimulatorTests: XCTestCase {

    var keySimulator: KeySimulator!
    var mockEventPoster: MockEventPoster!

    override func setUp() {
        super.setUp()
        mockEventPoster = MockEventPoster()
        keySimulator = KeySimulator(eventPoster: mockEventPoster)
    }

    override func tearDown() {
        keySimulator = nil
        mockEventPoster = nil
        super.tearDown()
    }

    // MARK: - 模拟回车键

    func testSimulateEnterKey() {
        // 模拟按下回车键
        let result = keySimulator.simulateEnter()

        XCTAssertTrue(result)
        XCTAssertTrue(mockEventPoster.didPostKeyDown)
        XCTAssertTrue(mockEventPoster.didPostKeyUp)
        XCTAssertEqual(mockEventPoster.lastKeyCode, KeySimulator.enterKeyCode)
    }

    func testSimulateEnterKeySequence() {
        // 回车键应该是先按下后释放
        let result = keySimulator.simulateEnter()

        XCTAssertTrue(result)
        XCTAssertEqual(mockEventPoster.eventSequence, ["keyDown", "keyUp"])
    }

    // MARK: - 删除字符

    func testDeleteCharacters() {
        // 删除指定数量的字符
        let result = keySimulator.deleteCharacters(count: 3)

        XCTAssertTrue(result)
        // 删除 3 个字符需要按 3 次 delete 键
        XCTAssertEqual(mockEventPoster.deleteKeyPressCount, 3)
    }

    func testDeleteZeroCharacters() {
        // 删除 0 个字符应该成功但不执行任何操作
        let result = keySimulator.deleteCharacters(count: 0)

        XCTAssertTrue(result)
        XCTAssertEqual(mockEventPoster.deleteKeyPressCount, 0)
    }

    func testDeleteNegativeCharactersFails() {
        // 删除负数字符应该失败
        let result = keySimulator.deleteCharacters(count: -1)

        XCTAssertFalse(result)
    }

    // MARK: - 组合操作：删除后回车

    func testDeleteThenEnter() {
        // 先删除字符，再按回车
        let result = keySimulator.deleteThenEnter(deleteCount: 2)

        XCTAssertTrue(result)
        // 先删除 2 个字符，再按回车
        XCTAssertEqual(mockEventPoster.deleteKeyPressCount, 2)
        XCTAssertEqual(mockEventPoster.lastKeyCode, KeySimulator.enterKeyCode)
    }

    func testDeleteThenEnterWithZeroDelete() {
        // 删除 0 个字符后按回车
        let result = keySimulator.deleteThenEnter(deleteCount: 0)

        XCTAssertTrue(result)
        XCTAssertEqual(mockEventPoster.deleteKeyPressCount, 0)
        XCTAssertEqual(mockEventPoster.lastKeyCode, KeySimulator.enterKeyCode)
    }

    func testDeleteThenEnterOperationOrder() {
        // 验证操作顺序：先删除，后回车
        let result = keySimulator.deleteThenEnter(deleteCount: 2)

        XCTAssertTrue(result)

        // 期望顺序：delete, delete, keyDown(enter), keyUp(enter)
        let expectedSequence = ["delete", "delete", "keyDown", "keyUp"]
        XCTAssertEqual(mockEventPoster.eventSequence, expectedSequence)
    }

    // MARK: - 错误处理

    func testSimulateEnterFailsWhenEventPosterFails() {
        // 当 EventPoster 失败时，simulateEnter 应该返回 false
        mockEventPoster.shouldFail = true

        let result = keySimulator.simulateEnter()

        XCTAssertFalse(result)
    }

    func testDeleteCharactersFailsWhenEventPosterFails() {
        // 当 EventPoster 失败时，deleteCharacters 应该返回 false
        mockEventPoster.shouldFail = true

        let result = keySimulator.deleteCharacters(count: 1)

        XCTAssertFalse(result)
    }
}

// MARK: - Mock EventPoster

/// Mock 事件发送器，用于测试 KeySimulator
class MockEventPoster: EventPosterProtocol {
    var didPostKeyDown = false
    var didPostKeyUp = false
    var lastKeyCode: CGKeyCode?
    var deleteKeyPressCount = 0
    var eventSequence: [String] = []
    var shouldFail = false

    func postKeyDown(keyCode: CGKeyCode) -> Bool {
        if shouldFail { return false }

        didPostKeyDown = true
        lastKeyCode = keyCode

        if keyCode == KeySimulator.deleteKeyCode {
            deleteKeyPressCount += 1
            eventSequence.append("delete")
        } else {
            eventSequence.append("keyDown")
        }

        return true
    }

    func postKeyUp(keyCode: CGKeyCode) -> Bool {
        if shouldFail { return false }

        didPostKeyUp = true
        lastKeyCode = keyCode

        if keyCode != KeySimulator.deleteKeyCode {
            eventSequence.append("keyUp")
        }

        return true
    }

    func reset() {
        didPostKeyDown = false
        didPostKeyUp = false
        lastKeyCode = nil
        deleteKeyPressCount = 0
        eventSequence = []
        shouldFail = false
    }
}
