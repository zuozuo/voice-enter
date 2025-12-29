import XCTest
@testable import VoiceEnterCore

final class TriggerWordDetectorTests: XCTestCase {

    var detector: TriggerWordDetector!

    override func setUp() {
        super.setUp()
        detector = TriggerWordDetector(triggerWords: ["发送", "Go"])
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - 基本触发词检测

    func testDetectsChineseTriggerWordAtEnd() {
        // 当输入以"发送"结尾时，应该检测到触发词
        let result = detector.detect(in: "你好发送")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "发送")
        XCTAssertEqual(result?.contentWithoutTrigger, "你好")
    }

    func testDetectsEnglishTriggerWordAtEnd() {
        // 当输入以"Go"结尾时，应该检测到触发词
        let result = detector.detect(in: "hello Go")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "Go")
        XCTAssertEqual(result?.contentWithoutTrigger, "hello ")
    }

    func testEnglishTriggerWordIsCaseInsensitive() {
        // "go"（小写）也应该被检测到
        let result = detector.detect(in: "hello go")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "go")
        XCTAssertEqual(result?.contentWithoutTrigger, "hello ")
    }

    func testEnglishTriggerWordUpperCase() {
        // "GO"（全大写）也应该被检测到
        let result = detector.detect(in: "hello GO")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "GO")
        XCTAssertEqual(result?.contentWithoutTrigger, "hello ")
    }

    // MARK: - 不应触发的情况

    func testDoesNotDetectTriggerWordInMiddle() {
        // 触发词在中间时，不应该触发
        let result = detector.detect(in: "请发送这个消息给他")

        XCTAssertNil(result)
    }

    func testDoesNotDetectWhenNoTriggerWord() {
        // 没有触发词时，不应该触发
        let result = detector.detect(in: "你好世界")

        XCTAssertNil(result)
    }

    func testDoesNotDetectEmptyInput() {
        // 空输入不应该触发
        let result = detector.detect(in: "")

        XCTAssertNil(result)
    }

    func testDoesNotDetectOnlyTriggerWord() {
        // 只有触发词本身，内容为空，不应该触发（避免误发空消息）
        let result = detector.detect(in: "发送")

        XCTAssertNil(result)
    }

    func testDoesNotDetectOnlyWhitespaceBeforeTrigger() {
        // 触发词前只有空格，不应该触发
        let result = detector.detect(in: "   发送")

        XCTAssertNil(result)
    }

    // MARK: - 边界情况

    func testDetectsWithTrailingWhitespace() {
        // 触发词后有空格，应该忽略空格并检测
        let result = detector.detect(in: "你好发送 ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "发送")
        XCTAssertEqual(result?.contentWithoutTrigger, "你好")
    }

    func testDetectsWithMultipleTrailingSpaces() {
        // 触发词后有多个空格
        let result = detector.detect(in: "你好发送   ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "发送")
        XCTAssertEqual(result?.contentWithoutTrigger, "你好")
    }

    func testDetectsWithNewlineAfterTrigger() {
        // 触发词后有换行符
        let result = detector.detect(in: "你好发送\n")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "发送")
        XCTAssertEqual(result?.contentWithoutTrigger, "你好")
    }

    func testPreservesLeadingWhitespaceInContent() {
        // 保留内容开头的空格
        let result = detector.detect(in: "  你好发送")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.contentWithoutTrigger, "  你好")
    }

    func testDetectsWithMixedChineseEnglish() {
        // 中英文混合内容
        let result = detector.detect(in: "hello世界发送")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "发送")
        XCTAssertEqual(result?.contentWithoutTrigger, "hello世界")
    }

    // MARK: - 多个触发词

    func testDetectsFirstMatchingTriggerWord() {
        // 如果内容同时以多个触发词结尾，应该匹配最后一个
        // 例如："发送Go" 应该匹配 "Go"
        let result = detector.detect(in: "你好发送Go")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.triggerWord, "Go")
    }

    // MARK: - 自定义触发词

    func testWorksWithCustomTriggerWords() {
        // 使用自定义触发词
        let customDetector = TriggerWordDetector(triggerWords: ["OK", "确定"])

        let result1 = customDetector.detect(in: "测试OK")
        XCTAssertNotNil(result1)
        XCTAssertEqual(result1?.triggerWord, "OK")

        let result2 = customDetector.detect(in: "测试确定")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.triggerWord, "确定")
    }

    func testEmptyTriggerWordsDetectsNothing() {
        // 没有触发词时，永远不触发
        let emptyDetector = TriggerWordDetector(triggerWords: [])

        let result = emptyDetector.detect(in: "你好发送")
        XCTAssertNil(result)
    }

    // MARK: - 更新触发词

    func testUpdateTriggerWords() {
        // 更新触发词后，应该使用新的触发词
        detector.updateTriggerWords(["执行", "Run"])

        // 旧触发词不应该匹配
        let result1 = detector.detect(in: "你好发送")
        XCTAssertNil(result1)

        // 新触发词应该匹配
        let result2 = detector.detect(in: "你好执行")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.triggerWord, "执行")
    }

    // MARK: - 特殊字符

    func testHandlesSpecialCharactersInContent() {
        // 内容包含特殊字符
        let result = detector.detect(in: "你好！@#$%发送")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.contentWithoutTrigger, "你好！@#$%")
    }

    func testHandlesEmojiInContent() {
        // 内容包含 emoji
        let result = detector.detect(in: "你好😀发送")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.contentWithoutTrigger, "你好😀")
    }

    func testHandlesMultilineContent() {
        // 多行内容
        let result = detector.detect(in: "第一行\n第二行发送")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.contentWithoutTrigger, "第一行\n第二行")
    }
}
