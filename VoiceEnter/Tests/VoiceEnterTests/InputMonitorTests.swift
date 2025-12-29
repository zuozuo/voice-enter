import XCTest
@testable import VoiceEnterCore

final class InputMonitorTests: XCTestCase {

    var inputMonitor: InputMonitor!
    var mockKeySimulator: MockKeySimulator!
    var mockSettingsManager: MockSettingsManager!

    override func setUp() {
        super.setUp()
        mockKeySimulator = MockKeySimulator()
        mockSettingsManager = MockSettingsManager()
        inputMonitor = InputMonitor(
            keySimulator: mockKeySimulator,
            settingsManager: mockSettingsManager
        )
    }

    override func tearDown() {
        inputMonitor = nil
        mockKeySimulator = nil
        mockSettingsManager = nil
        super.tearDown()
    }

    // MARK: - 基本触发

    func testTriggersOnValidInput() {
        // 当输入以触发词结尾时，应该触发删除+回车
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        inputMonitor.handleTextInput("你好发送")

        // 等待防抖延迟
        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(mockKeySimulator.didDeleteThenEnter)
        XCTAssertEqual(mockKeySimulator.lastDeleteCount, 2) // "发送" 是 2 个字符
    }

    func testDoesNotTriggerWhenDisabled() {
        // 当功能关闭时，不应该触发
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = false

        inputMonitor.handleTextInput("你好发送")

        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(mockKeySimulator.didDeleteThenEnter)
    }

    func testDoesNotTriggerWithoutTriggerWord() {
        // 没有触发词时，不应该触发
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        inputMonitor.handleTextInput("你好世界")

        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(mockKeySimulator.didDeleteThenEnter)
    }

    // MARK: - 防抖机制

    func testDebouncesPreviousInput() {
        // 快速连续输入时，应该取消前一次的触发
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        // 第一次输入
        inputMonitor.handleTextInput("你好发送")

        // 100ms 后继续输入（在防抖窗口内）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.inputMonitor.handleTextInput("你好发送继续输入")
        }

        // 等待足够长的时间
        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // 因为继续输入后没有触发词结尾，所以不应该触发
        XCTAssertFalse(mockKeySimulator.didDeleteThenEnter)
    }

    func testTriggersAfterDebounceDelay() {
        // 防抖延迟后，如果没有新输入，应该触发
        mockSettingsManager.mockTriggerWords = ["Go"]
        mockSettingsManager.mockIsEnabled = true

        inputMonitor.handleTextInput("hello Go")

        // 等待防抖延迟（默认 300ms）+ 一点余量
        let expectation = XCTestExpectation(description: "Trigger after debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(mockKeySimulator.didDeleteThenEnter)
    }

    // MARK: - 删除字符数计算

    func testDeletesCorrectNumberOfChineseCharacters() {
        // 删除中文触发词时，字符数应该正确
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        inputMonitor.handleTextInput("你好发送")

        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockKeySimulator.lastDeleteCount, 2) // "发送" = 2 个字符
    }

    func testDeletesCorrectNumberOfEnglishCharacters() {
        // 删除英文触发词时，字符数应该正确
        mockSettingsManager.mockTriggerWords = ["Go"]
        mockSettingsManager.mockIsEnabled = true

        inputMonitor.handleTextInput("hello Go")

        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockKeySimulator.lastDeleteCount, 2) // "Go" = 2 个字符
    }

    func testDeletesTrailingWhitespace() {
        // 触发词后的空格也应该被删除
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        inputMonitor.handleTextInput("你好发送  ")

        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockKeySimulator.lastDeleteCount, 4) // "发送  " = 4 个字符
    }

    // MARK: - 状态管理

    func testStartMonitoring() {
        // 启动监听后，isMonitoring 应该为 true
        inputMonitor.startMonitoring()

        XCTAssertTrue(inputMonitor.isMonitoring)
    }

    func testStopMonitoring() {
        // 停止监听后，isMonitoring 应该为 false
        inputMonitor.startMonitoring()
        inputMonitor.stopMonitoring()

        XCTAssertFalse(inputMonitor.isMonitoring)
    }

    func testDoesNotTriggerWhenNotMonitoring() {
        // 未启动监听时，不应该触发
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        // 注意：没有调用 startMonitoring()
        inputMonitor.handleTextInput("你好发送")

        let expectation = XCTestExpectation(description: "Debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(mockKeySimulator.didDeleteThenEnter)
    }

    // MARK: - 回调

    func testCallsOnTriggerCallback() {
        // 触发时应该调用回调
        mockSettingsManager.mockTriggerWords = ["发送"]
        mockSettingsManager.mockIsEnabled = true

        var callbackCalled = false
        var triggeredWord: String?

        inputMonitor.onTrigger = { word in
            callbackCalled = true
            triggeredWord = word
        }

        inputMonitor.startMonitoring()
        inputMonitor.handleTextInput("你好发送")

        let expectation = XCTestExpectation(description: "Callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(callbackCalled)
        XCTAssertEqual(triggeredWord, "发送")
    }
}

// MARK: - Mock KeySimulator

class MockKeySimulator: KeySimulatorProtocol {
    var didDeleteThenEnter = false
    var lastDeleteCount: Int?

    func deleteThenEnter(deleteCount: Int) -> Bool {
        didDeleteThenEnter = true
        lastDeleteCount = deleteCount
        return true
    }

    func simulateEnter() -> Bool {
        return true
    }

    func deleteCharacters(count: Int) -> Bool {
        return true
    }
}

// MARK: - Mock SettingsManager

class MockSettingsManager: SettingsManagerProtocol {
    var mockIsEnabled = true
    var mockTriggerWords = ["发送", "Go"]

    var isEnabled: Bool {
        get { mockIsEnabled }
        set { mockIsEnabled = newValue }
    }

    var triggerWords: [String] {
        mockTriggerWords
    }

    func addTriggerWord(_ word: String) -> Bool { true }
    func removeTriggerWord(_ word: String) -> Bool { true }
    func resetToDefault() {}
    func onSettingsChanged(_ callback: @escaping () -> Void) -> Cancellable {
        return MockCancellable()
    }
}

class MockCancellable: Cancellable {
    func cancel() {}
}
