import XCTest
@testable import VoiceEnterCore

final class SettingsManagerTests: XCTestCase {

    var settingsManager: SettingsManager!
    var mockUserDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // 使用独立的 UserDefaults suite 进行测试，避免污染真实设置
        mockUserDefaults = UserDefaults(suiteName: "com.voiceenter.tests")!
        mockUserDefaults.removePersistentDomain(forName: "com.voiceenter.tests")
        settingsManager = SettingsManager(userDefaults: mockUserDefaults)
    }

    override func tearDown() {
        mockUserDefaults.removePersistentDomain(forName: "com.voiceenter.tests")
        mockUserDefaults = nil
        settingsManager = nil
        super.tearDown()
    }

    // MARK: - 默认值测试

    func testDefaultEnabledIsTrue() {
        // 默认情况下，功能应该是开启的
        XCTAssertTrue(settingsManager.isEnabled)
    }

    func testDefaultTriggerWords() {
        // 默认触发词应该是 ["发送", "Go"]
        let triggerWords = settingsManager.triggerWords

        XCTAssertEqual(triggerWords.count, 2)
        XCTAssertTrue(triggerWords.contains("发送"))
        XCTAssertTrue(triggerWords.contains("Go"))
    }

    // MARK: - 开关状态

    func testSetEnabledTrue() {
        // 设置开启状态
        settingsManager.isEnabled = true

        XCTAssertTrue(settingsManager.isEnabled)
    }

    func testSetEnabledFalse() {
        // 设置关闭状态
        settingsManager.isEnabled = false

        XCTAssertFalse(settingsManager.isEnabled)
    }

    func testEnabledStatePersists() {
        // 开关状态应该持久化
        settingsManager.isEnabled = false

        // 创建新的 SettingsManager 实例，模拟重启应用
        let newSettingsManager = SettingsManager(userDefaults: mockUserDefaults)

        XCTAssertFalse(newSettingsManager.isEnabled)
    }

    // MARK: - 触发词管理

    func testAddTriggerWord() {
        // 添加新触发词
        let result = settingsManager.addTriggerWord("OK")

        XCTAssertTrue(result)
        XCTAssertTrue(settingsManager.triggerWords.contains("OK"))
    }

    func testAddDuplicateTriggerWordFails() {
        // 添加重复的触发词应该失败
        _ = settingsManager.addTriggerWord("OK")
        let result = settingsManager.addTriggerWord("OK")

        XCTAssertFalse(result)
        XCTAssertEqual(settingsManager.triggerWords.filter { $0 == "OK" }.count, 1)
    }

    func testAddDuplicateTriggerWordCaseInsensitive() {
        // 英文触发词重复检查应该不区分大小写
        _ = settingsManager.addTriggerWord("OK")
        let result = settingsManager.addTriggerWord("ok")

        XCTAssertFalse(result)
    }

    func testAddEmptyTriggerWordFails() {
        // 添加空触发词应该失败
        let result = settingsManager.addTriggerWord("")

        XCTAssertFalse(result)
    }

    func testAddWhitespaceTriggerWordFails() {
        // 添加只有空格的触发词应该失败
        let result = settingsManager.addTriggerWord("   ")

        XCTAssertFalse(result)
    }

    func testAddTriggerWordTooLongFails() {
        // 触发词超过 10 个字符应该失败
        let result = settingsManager.addTriggerWord("这是一个超过十个字的触发词")

        XCTAssertFalse(result)
    }

    func testAddTriggerWordExactly10CharactersSucceeds() {
        // 刚好 10 个字符应该成功
        let result = settingsManager.addTriggerWord("1234567890")

        XCTAssertTrue(result)
    }

    func testRemoveTriggerWord() {
        // 删除触发词
        let result = settingsManager.removeTriggerWord("发送")

        XCTAssertTrue(result)
        XCTAssertFalse(settingsManager.triggerWords.contains("发送"))
    }

    func testRemoveNonExistentTriggerWordFails() {
        // 删除不存在的触发词应该失败
        let result = settingsManager.removeTriggerWord("不存在的词")

        XCTAssertFalse(result)
    }

    func testCannotRemoveLastTriggerWord() {
        // 不能删除最后一个触发词
        _ = settingsManager.removeTriggerWord("发送")

        // 此时只剩 "Go" 一个触发词
        let result = settingsManager.removeTriggerWord("Go")

        XCTAssertFalse(result)
        XCTAssertEqual(settingsManager.triggerWords.count, 1)
        XCTAssertTrue(settingsManager.triggerWords.contains("Go"))
    }

    func testTriggerWordsPersist() {
        // 触发词应该持久化
        _ = settingsManager.addTriggerWord("OK")
        _ = settingsManager.removeTriggerWord("发送")

        // 创建新的 SettingsManager 实例
        let newSettingsManager = SettingsManager(userDefaults: mockUserDefaults)

        XCTAssertTrue(newSettingsManager.triggerWords.contains("Go"))
        XCTAssertTrue(newSettingsManager.triggerWords.contains("OK"))
        XCTAssertFalse(newSettingsManager.triggerWords.contains("发送"))
    }

    // MARK: - 恢复默认

    func testResetToDefault() {
        // 修改设置
        settingsManager.isEnabled = false
        _ = settingsManager.addTriggerWord("OK")
        _ = settingsManager.removeTriggerWord("发送")

        // 恢复默认
        settingsManager.resetToDefault()

        // 验证恢复到默认状态
        XCTAssertTrue(settingsManager.isEnabled)
        XCTAssertEqual(settingsManager.triggerWords.count, 2)
        XCTAssertTrue(settingsManager.triggerWords.contains("发送"))
        XCTAssertTrue(settingsManager.triggerWords.contains("Go"))
    }

    // MARK: - 触发词去空格

    func testAddTriggerWordTrimsWhitespace() {
        // 添加触发词时应该去除首尾空格
        let result = settingsManager.addTriggerWord("  OK  ")

        XCTAssertTrue(result)
        XCTAssertTrue(settingsManager.triggerWords.contains("OK"))
        XCTAssertFalse(settingsManager.triggerWords.contains("  OK  "))
    }

    // MARK: - 观察者模式（可选实现）

    func testSettingsChangeNotification() {
        // 设置变化时应该发送通知
        let expectation = XCTestExpectation(description: "Settings change notification")

        let cancellable = settingsManager.onSettingsChanged {
            expectation.fulfill()
        }

        settingsManager.isEnabled = false

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}
