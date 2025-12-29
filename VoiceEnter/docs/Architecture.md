# VoiceEnter 架构设计文档

## 文档信息

| 属性 | 值 |
|------|-----|
| 版本 | 1.0 |
| 更新日期 | 2024-12 |

---

## 1. 系统概述

### 1.1 架构目标

- **模块化** - 各监听器独立，便于扩展
- **低耦合** - 通过协议抽象，组件可替换
- **高性能** - 低 CPU 占用，快速响应
- **可测试** - 核心逻辑可单元测试

### 1.2 技术栈

| 层级 | 技术选型 |
|------|---------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI |
| 包管理 | Swift Package Manager |
| 平台 | macOS 13.0+ |
| 架构模式 | MVVM + Observer |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         VoiceEnterApp                            │
│                      (SwiftUI Application)                       │
├─────────────────────────────────────────────────────────────────┤
│                           AppState                               │
│                    (Observable ViewModel)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  isEnabled  │  │triggerWords │  │     triggerScope        │  │
│  │  isRunning  │  │             │  │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                     VoiceEnterCore                               │
│                    (Business Logic)                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │               UniversalInputMonitor                      │    │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐    │    │
│  │  │ TextMonitor │ │KittyMonitor │ │TerminalMonitor  │    │    │
│  │  │ (Accessibility)│ (kitty @)  │ │  (AppleScript)  │    │    │
│  │  └─────────────┘ └─────────────┘ └─────────────────┘    │    │
│  │  ┌─────────────────────────────────────────────────┐    │    │
│  │  │           FaceExpressionMonitor                  │    │    │
│  │  │         (Vision + AVFoundation)                  │    │    │
│  │  └─────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │               TriggerWordDetector                        │    │
│  │           检测文本末尾是否包含触发词                       │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   KeySimulator                           │    │
│  │              模拟删除 + 回车按键                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  SettingsManager                         │    │
│  │              持久化设置 (UserDefaults)                    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        macOS System                              │
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────────────┐   │
│  │Accessibility │ │  CGEvent     │ │ AVFoundation + Vision  │   │
│  │     API      │ │    API       │ │                        │   │
│  └──────────────┘ └──────────────┘ └────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 模块划分

| 模块 | 职责 | 依赖 |
|------|------|------|
| VoiceEnterApp | 应用入口、UI 层 | VoiceEnterCore |
| VoiceEnterCore | 核心业务逻辑 | Foundation, AppKit |
| Tests | 单元测试 | VoiceEnterCore |

---

## 3. 核心组件设计

### 3.1 UniversalInputMonitor

**职责：** 统一管理多种输入监听方式

```swift
public class UniversalInputMonitor {
    // 各类监听器
    private let textMonitor: TextMonitor
    private let kittyMonitor: KittyTerminalMonitor
    private let terminalMonitor: TerminalAppMonitor
    public let faceMonitor: FaceExpressionMonitor

    // 回调
    public var onTrigger: ((String) -> Void)?
    public var onExpressionChange: ((ExpressionState) -> Void)?
    public var onStatusChange: ((Bool) -> Void)?

    // 生命周期
    public func startMonitoring() -> Bool
    public func stopMonitoring()
}
```

**设计决策：**
- 使用组合模式，聚合多个监听器
- 任一监听器成功即算启动成功
- 统一触发回调接口

### 3.2 KittyTerminalMonitor

**职责：** 监听 Kitty 终端中的文本输入

**技术方案：**
```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│  Timer       │────▶│  kitty @ get-text │────▶│ extractInputLine│
│  (0.15s)     │     │                   │     │                 │
└──────────────┘     └───────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│  触发回车    │◀────│ TriggerDetector   │◀────│   防抖处理       │
│              │     │                   │     │   (0.6s)        │
└──────────────┘     └───────────────────┘     └─────────────────┘
```

**关键逻辑：**

1. **轮询获取文本**
   - 使用 `kitty @ get-text` 命令获取终端内容
   - 轮询间隔 0.15 秒

2. **提取用户输入行**
   - 支持 Claude Code 模式：识别 `> ` 提示符
   - 支持 Shell 模式：识别 `$ ` 或 `% ` 提示符
   - 过滤状态行和代码行

3. **防抖处理**
   - 文本变化后延迟 0.6 秒再检测
   - 避免输入过程中频繁触发

### 3.3 TextMonitor

**职责：** 使用 Accessibility API 监听通用应用

**技术方案：**
```swift
// 获取系统焦点元素
let systemWide = AXUIElementCreateSystemWide()
AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focusedElement)

// 获取文本值
AXUIElementCopyAttributeValue(element, kAXValueAttribute, &value)
```

**触发范围控制：**
```swift
// TextMonitor 只在 allApps 模式下工作
guard settingsManager.triggerScope == .allApps else { return }
```

### 3.4 TerminalAppMonitor

**职责：** 使用 AppleScript 监听 Terminal.app

**技术方案：**
```applescript
tell application "Terminal"
    if (count of windows) > 0 then
        return contents of front window
    end if
end tell
```

**触发范围控制：**
```swift
// 在 terminalsOnly 和 allApps 模式下工作
guard settingsManager.triggerScope != .kittyOnly else { return }
```

### 3.5 FaceExpressionMonitor

**职责：** 通过摄像头检测面部表情触发

**技术方案：**
```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│ AVCapture    │────▶│ VNDetectFace      │────▶│ ExpressionState │
│ Session      │     │ LandmarksRequest  │     │                 │
└──────────────┘     └───────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│  触发回车    │◀────│ shouldTrigger()   │◀────│  持续时间检测    │
│              │     │                   │     │                 │
└──────────────┘     └───────────────────┘     └─────────────────┘
```

详细设计见 [FaceExpressionMonitor-Design.md](./FaceExpressionMonitor-Design.md)

### 3.6 TriggerWordDetector

**职责：** 检测文本末尾是否包含触发词

```swift
public struct TriggerResult {
    public let triggerWord: String
    public let position: String.Index
}

public class TriggerWordDetector {
    public func detect(in text: String) -> TriggerResult?
    public func updateTriggerWords(_ words: [String])
}
```

**检测逻辑：**
1. 去除尾部空白和标点
2. 检查文本是否以触发词结尾
3. 英文不区分大小写

### 3.7 KeySimulator

**职责：** 模拟键盘按键操作

```swift
public class KeySimulator {
    public func deleteThenEnter(deleteCount: Int) -> Bool
    public func pressEnter() -> Bool
    public func pressDelete(count: Int) -> Bool
}
```

**实现方案：**
```swift
// 使用 CGEvent 模拟按键
let event = CGEvent(keyboardEventSource: nil,
                    virtualKey: keyCode,
                    keyDown: true)
event?.post(tap: .cghidEventTap)
```

### 3.8 SettingsManager

**职责：** 管理应用设置的持久化

```swift
public enum TriggerScope: Int, CaseIterable, Codable {
    case kittyOnly = 0      // 仅 Kitty 终端
    case terminalsOnly = 1  // 仅终端类应用
    case allApps = 2        // 所有应用
}

public class SettingsManager {
    public var isEnabled: Bool
    public var triggerWords: [String]
    public var triggerScope: TriggerScope

    public func addTriggerWord(_ word: String) -> Bool
    public func removeTriggerWord(_ word: String) -> Bool
    public func onSettingsChanged(_ callback: @escaping () -> Void) -> Cancellable
}
```

**存储方案：** UserDefaults

---

## 4. 数据流

### 4.1 触发词检测流程

```
┌─────────────────────────────────────────────────────────────────┐
│                          用户输入                                │
│                    "你好，帮我查天气发送"                          │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Monitor 轮询检测                            │
│                      (每 0.15-0.2 秒)                           │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        文本变化检测                              │
│               lastText != currentText ?                         │
└─────────────────────────────────────────────────────────────────┘
                               │ 是
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        防抖延迟                                  │
│                    等待 0.5-0.6 秒                               │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   TriggerWordDetector                           │
│                   检测末尾触发词 "发送"                          │
└─────────────────────────────────────────────────────────────────┘
                               │ 匹配
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      KeySimulator                               │
│              删除 2 个字符 + 回车                                │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        消息发送                                  │
│                    "你好，帮我查天气"                             │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 设置变更流程

```
┌─────────┐     ┌─────────────────┐     ┌─────────────────┐
│   UI    │────▶│  SettingsManager │────▶│   UserDefaults  │
│ Toggle  │     │                 │     │                 │
└─────────┘     └─────────────────┘     └─────────────────┘
                        │
                        ▼ 通知
┌─────────────────────────────────────────────────────────┐
│                    监听器更新                            │
│  - TextMonitor 检查 triggerScope                        │
│  - TerminalMonitor 检查 triggerScope                    │
│  - KittyMonitor 更新 triggerWords                       │
└─────────────────────────────────────────────────────────┘
```

---

## 5. UI 架构

### 5.1 视图层级

```
VoiceEnterApp (@main)
└── MenuBarExtra ("VoiceEnter")
    └── MenuBarView
        ├── headerSection
        │   ├── 标题 "VoiceEnter"
        │   └── 状态指示器
        ├── mainControlCard
        │   ├── 启用开关
        │   └── 触发范围选择器
        ├── triggerWordsCard
        │   ├── 触发词标签列表 (FlowLayout)
        │   └── 添加按钮
        ├── faceExpressionCard
        │   ├── 摄像头状态
        │   └── 表情检测状态
        └── footerSection
            └── 退出按钮
```

### 5.2 设计系统

```swift
// 颜色系统
enum DesignColors {
    static let background = Color(hex: "141414")
    static let cardBackground = Color(hex: "1F1F1F")
    static let cardHover = Color(hex: "262626")
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "2DD4BF"), Color(hex: "3B82F6")],
        ...
    )
}

// 组件
- CardStyle: ViewModifier
- StatusIndicator: View
- SectionHeader: View
- StyledToggle: View
- TriggerWordTag: View
- PrimaryActionButton: View
- FlowLayout: Layout
```

---

## 6. 错误处理

### 6.1 错误类型

| 错误场景 | 处理方式 |
|---------|---------|
| 辅助功能权限缺失 | 提示用户授权，继续其他监听器 |
| Kitty 未运行 | 跳过 KittyMonitor |
| Terminal 未运行 | 跳过 TerminalMonitor |
| 摄像头权限缺失 | 跳过 FaceMonitor |
| 按键模拟失败 | 记录日志，不中断 |

### 6.2 降级策略

```
优先级高 ──────────────────────────────────▶ 优先级低

KittyMonitor ──▶ TerminalMonitor ──▶ TextMonitor ──▶ FaceMonitor
   (kitty @)      (AppleScript)     (Accessibility)    (Vision)
```

---

## 7. 测试策略

### 7.1 测试分类

| 类型 | 覆盖范围 | 位置 |
|------|---------|------|
| 单元测试 | TriggerWordDetector, SettingsManager | Tests/ |
| 集成测试 | KeySimulator (需权限) | Tests/ |
| 手动测试 | 完整流程 | - |

### 7.2 测试用例示例

```swift
// TriggerWordDetector 测试
func testDetectTriggerWordAtEnd() {
    let detector = TriggerWordDetector(triggerWords: ["发送"])
    let result = detector.detect(in: "你好发送")
    XCTAssertEqual(result?.triggerWord, "发送")
}

// SettingsManager 测试
func testAddDuplicateTriggerWord() {
    let manager = SettingsManager()
    manager.addTriggerWord("Go")
    XCTAssertFalse(manager.addTriggerWord("go")) // 不区分大小写
}
```

---

## 8. 日志系统

### 8.1 日志格式

```
[ISO8601时间] [模块] 消息
```

示例：
```
[2024-12-29T18:50:04Z] [UniversalMonitor] 启动通用输入监听器
[2024-12-29T18:50:04Z] [KittyMonitor] 开始监听 kitty 终端，触发词: ["发送", "Go"]
[2024-12-29T18:50:13Z] [KittyMonitor] 输入行变化: '' -> '你好发送'
[2024-12-29T18:50:13Z] [KittyMonitor] ✅ 检测到触发词 '发送'，删除 2 个字符后回车
```

### 8.2 日志位置

```
/tmp/voiceenter.log
```

查看实时日志：
```bash
tail -f /tmp/voiceenter.log
```

---

## 9. 性能优化

### 9.1 CPU 优化

| 优化措施 | 效果 |
|---------|------|
| 轮询间隔 0.15-0.2s | 平衡响应速度和 CPU 占用 |
| 防抖处理 | 减少不必要的检测 |
| 文本变化检测 | 内容无变化时跳过处理 |
| 按需启动监听器 | 不需要的监听器不启动 |

### 9.2 内存优化

| 优化措施 | 效果 |
|---------|------|
| 弱引用回调 | 避免循环引用 |
| 及时清理 Timer | 停止时释放资源 |
| 不缓存终端内容 | 只保留最后一次文本 |

---

## 10. 扩展性设计

### 10.1 添加新监听器

1. 实现监听逻辑类
2. 添加到 UniversalInputMonitor
3. 在 TriggerScope 中添加对应选项（可选）

### 10.2 添加新触发动作

当前只支持"删除 + 回车"，未来可扩展：
- 删除 + 粘贴
- 删除 + 快捷键
- 自定义脚本执行

---

## 附录

### A. 相关文档

- [PRD.md](./PRD.md) - 产品需求文档
- [FaceExpressionMonitor-Design.md](./FaceExpressionMonitor-Design.md) - 表情监听设计

### B. 参考资料

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/accessibility)
- [Kitty Remote Control](https://sw.kovidgoyal.net/kitty/remote-control/)
- [CGEvent Reference](https://developer.apple.com/documentation/coregraphics/cgevent)
