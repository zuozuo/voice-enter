# VoiceEnter 架构设计文档

## 文档信息

| 属性 | 值 |
|------|-----|
| 版本 | 1.1 |
| 更新日期 | 2025-12 |
| 状态 | 已实现 |

---

## 1. 系统概述

### 1.1 架构目标

- **模块化** - 各监听器独立，便于扩展
- **低耦合** - 通过协议抽象，组件可替换
- **高性能** - 低 CPU 占用，快速响应
- **可测试** - 核心逻辑可单元测试
- **隐私优先** - 全部本地处理，无外部依赖

### 1.2 技术栈

| 层级 | 技术选型 |
|------|---------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI |
| 包管理 | Swift Package Manager |
| 平台 | macOS 13.0+ |
| 架构模式 | MVVM + Observer |

### 1.3 系统 API 依赖

| API | 用途 |
|-----|------|
| CGEvent | 按键模拟（回车、删除） |
| Accessibility API | 通用应用文本监听 |
| AVFoundation | 摄像头采集 |
| Vision Framework | 人脸关键点检测 |
| AppleScript | Terminal.app 监听 |
| UserDefaults | 设置持久化 |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              VoiceEnterApp                                   │
│                           (SwiftUI Application)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                            AppState                                   │   │
│  │                     (Observable ViewModel)                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │ isMonitoring│  │triggerWords │  │triggerScope │  │ themeMode   │  │   │
│  │  │ isEnabled   │  │ lastTriggered│  │triggerSound │  │ expression  │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                              VoiceEnterCore                                  │
│                            (Business Logic)                                  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      UniversalInputMonitor                            │   │
│  │                         (监听协调器)                                   │   │
│  │  ┌────────────────┐ ┌────────────────┐ ┌────────────────────────┐    │   │
│  │  │  TextMonitor   │ │ KittyTerminal  │ │  TerminalAppMonitor    │    │   │
│  │  │ (Accessibility)│ │   Monitor      │ │    (AppleScript)       │    │   │
│  │  └────────────────┘ └────────────────┘ └────────────────────────┘    │   │
│  │  ┌────────────────────────────────────────────────────────────────┐  │   │
│  │  │                   FaceExpressionMonitor                         │  │   │
│  │  │                  (Vision + AVFoundation)                        │  │   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │  │   │
│  │  │  │CameraCapture │→ │FaceDetector  │→ │ExpressionAnalyzer    │  │  │   │
│  │  │  │(AVCapture)   │  │(VNLandmarks) │  │ (关键点→系数)         │  │  │   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      TriggerWordDetector                              │   │
│  │                    检测文本末尾是否包含触发词                           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         KeySimulator                                  │   │
│  │                     模拟删除 + 回车按键                                │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                       SettingsManager                                 │   │
│  │                   持久化设置 (UserDefaults)                           │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              macOS System                                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐  │
│  │ Accessibility│ │   CGEvent    │ │ AVFoundation │ │      Vision        │  │
│  │     API      │ │     API      │ │              │ │    Framework       │  │
│  └──────────────┘ └──────────────┘ └──────────────┘ └────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块划分

| 模块 | 职责 | 依赖 |
|------|------|------|
| VoiceEnterApp | 应用入口、UI 层、状态管理 | VoiceEnterCore, SwiftUI |
| VoiceEnterCore | 核心业务逻辑 | Foundation, AppKit, AVFoundation, Vision |
| Tests | 单元测试 | VoiceEnterCore, XCTest |

### 2.3 目录结构

```
VoiceEnter/
├── Package.swift                    # Swift Package 配置
├── Sources/
│   ├── VoiceEnterApp/              # 应用层
│   │   └── VoiceEnterApp.swift     # 主程序、UI、状态管理 (~1000行)
│   └── VoiceEnterCore/             # 核心业务层
│       ├── Protocols.swift         # 协议定义
│       ├── TriggerWordDetector.swift    # 触发词检测
│       ├── SettingsManager.swift        # 设置管理
│       ├── KeySimulator.swift           # 按键模拟
│       ├── InputMonitor.swift           # 基础输入监听
│       ├── UniversalInputMonitor.swift  # 统一监听协调器
│       ├── TextMonitor.swift            # Accessibility API 监听
│       ├── KittyTerminalMonitor.swift   # Kitty 终端监听
│       ├── TerminalAppMonitor.swift     # Terminal.app 监听
│       ├── HybridInputMonitor.swift     # 混合事件监听
│       └── FaceExpressionMonitor.swift  # 面部表情监听
└── Tests/
    └── VoiceEnterTests/            # 单元测试 (62个用例)
        ├── TriggerWordDetectorTests.swift
        ├── SettingsManagerTests.swift
        ├── KeySimulatorTests.swift
        └── InputMonitorTests.swift
```

---

## 3. 核心组件设计

### 3.1 UniversalInputMonitor（监听协调器）

**职责：** 统一管理多种输入监听方式，协调各监听器的启动和停止。

```swift
public class UniversalInputMonitor {
    // 各类监听器
    private let textMonitor: TextMonitor
    private let kittyMonitor: KittyTerminalMonitor
    private let terminalMonitor: TerminalAppMonitor
    public let faceMonitor: FaceExpressionMonitor

    // 回调接口
    public var onTrigger: ((String) -> Void)?
    public var onExpressionChange: ((ExpressionState) -> Void)?
    public var onStatusChange: ((Bool) -> Void)?

    // 生命周期
    public func startMonitoring() -> Bool
    public func stopMonitoring()

    // 权限检查
    public func checkAccessibilityPermission() -> Bool
    public func requestAccessibilityPermission()
}
```

**设计决策：**
- 使用组合模式，聚合多个监听器
- 任一监听器成功即算启动成功
- 统一触发回调接口，外部无需关心具体监听器

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

**关键特性：**

1. **轮询获取文本** - 使用 `kitty @ get-text` 命令，轮询间隔 0.15 秒
2. **多模式支持**
   - Claude Code 模式：识别 `> ` 提示符
   - Shell 模式：识别 `$ ` 或 `% ` 提示符
3. **防抖处理** - 文本变化后延迟 0.6 秒再检测

### 3.3 TextMonitor

**职责：** 使用 Accessibility API 监听通用应用文本输入

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

```applescript
tell application "Terminal"
    if (count of windows) > 0 then
        return contents of front window
    end if
end tell
```

**触发范围：** 在 `terminalsOnly` 和 `allApps` 模式下工作

### 3.5 FaceExpressionMonitor

**职责：** 通过摄像头检测面部表情触发回车

**数据流：**
```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│ AVCapture    │────▶│ VNDetectFace      │────▶│ ExpressionState │
│ Session      │     │ LandmarksRequest  │     │  (系数计算)      │
│ (15fps)      │     │ (76个关键点)       │     │                 │
└──────────────┘     └───────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│  触发回车    │◀────│ shouldTrigger()   │◀────│  持续时间检测    │
│  播放音效    │     │ (阈值+冷却)        │     │  侧脸过滤        │
└──────────────┘     └───────────────────┘     └─────────────────┘
```

**核心类：**

```swift
/// 表情类型枚举
public enum ExpressionType: String, CaseIterable, Codable {
    case mouthOpen = "张嘴"       // 默认阈值 0.15, 持续 0.3s
    case pout = "撅嘴"           // 默认阈值 0.15, 持续 0.3s
    case leftEyeBlink = "左眼眨眼"  // 默认阈值 0.6, 持续 0.15s
    case rightEyeBlink = "右眼眨眼" // 默认阈值 0.6, 持续 0.15s
    case bothEyesBlink = "双眼眨眼" // 默认阈值 0.6, 持续 0.15s
    case eyebrowRaise = "挑眉"    // 默认阈值 0.3, 持续 0.3s
    case smile = "微笑"          // 默认阈值 0.4, 持续 0.5s
}

/// 表情状态
public struct ExpressionState {
    var coefficients: [ExpressionType: Float]  // 各表情系数 (0.0~1.0)
    var hasFace: Bool                          // 是否检测到人脸
}

/// 面部表情监听器
public class FaceExpressionMonitor {
    var triggerExpression: ExpressionType  // 当前触发表情
    var threshold: Float                   // 触发阈值
    var minDuration: TimeInterval          // 最小持续时间
    var cooldown: TimeInterval             // 冷却时间 (默认 1.0s)
    var triggerSound: TriggerSound         // 触发音效

    func startMonitoring() -> Bool
    func stopMonitoring()
    func checkCameraPermission() -> Bool
    func hasCameraDevice() -> Bool
}
```

**表情计算算法：**

```swift
/// 张嘴检测 - 基于内嘴唇上下距离与人脸高度的比例
private func calculateMouthOpen(_ landmarks: VNFaceLandmarks2D, faceBounds: CGRect) -> Float {
    guard let innerLips = landmarks.innerLips else { return 0 }
    let points = innerLips.normalizedPoints

    // 内嘴唇上下距离
    let topPoint = points[0]
    let bottomPoint = points[points.count / 2]
    let mouthHeight = abs(topPoint.y - bottomPoint.y)

    // 正常闭嘴 ~0.02-0.04，张大嘴 ~0.15-0.25
    let normalized = min(max((mouthHeight - 0.04) / 0.15, 0), 1)
    return Float(normalized)
}

/// 撅嘴检测 - 基于嘴巴宽度缩小和嘴唇厚度增加
private func calculatePout(_ landmarks: VNFaceLandmarks2D, faceBounds: CGRect) -> Float {
    // 嘴巴宽度变窄 (70% 权重) + 嘴唇厚度增加 (30% 权重)
    let widthFactor = max(0, (0.14 - mouthWidth) / 0.06)
    let thicknessFactor = max(0, (lipThickness - 0.015) / 0.025)
    return Float(widthFactor * 0.7 + thicknessFactor * 0.3)
}
```

**防误触机制：**
1. **侧脸过滤** - 人脸宽高比 < 0.5 时跳过检测
2. **持续时间** - 表情需保持指定时间才触发
3. **冷却时间** - 触发后需等待才能再次触发

### 3.6 TriggerWordDetector

**职责：** 检测文本末尾是否包含触发词

```swift
public struct TriggerDetectionResult {
    public let triggerWord: String           // 匹配的触发词
    public let contentWithoutTrigger: String // 去除触发词的内容
}

public class TriggerWordDetector {
    public func detect(in text: String) -> TriggerDetectionResult?
    public func updateTriggerWords(_ words: [String])
}
```

**检测逻辑：**
1. 去除尾部空白和中文标点（。！？，；：～等）
2. 检查文本是否以触发词结尾
3. 英文不区分大小写，中文精确匹配
4. 返回匹配的触发词和去除触发词后的内容

### 3.7 KeySimulator

**职责：** 模拟键盘按键操作

```swift
public class KeySimulator {
    public func simulateEnter() -> Bool           // 模拟回车
    public func simulateDelete(count: Int) -> Bool // 模拟删除
    public func deleteThenEnter(deleteCount: Int) -> Bool // 组合操作
}
```

**实现：**
```swift
// 使用 CGEvent 模拟按键
let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
keyDown?.post(tap: .cghidEventTap)
keyUp?.post(tap: .cghidEventTap)

// 虚拟键码
let enterKeyCode: CGKeyCode = 36
let deleteKeyCode: CGKeyCode = 51
```

### 3.8 SettingsManager

**职责：** 管理应用设置的持久化

```swift
/// 触发范围
public enum TriggerScope: Int, CaseIterable, Codable {
    case kittyOnly = 0      // 仅 Kitty 终端
    case terminalsOnly = 1  // Kitty + Terminal.app
    case allApps = 2        // 所有应用
}

/// 触发音效
public enum TriggerSound: String, CaseIterable, Codable {
    case none = "无"
    case tink = "Tink"      // 默认
    case pop = "Pop"
    case ping = "Ping"
    // ... 共 14 种
}

public class SettingsManager {
    var isEnabled: Bool              // 启用/禁用
    var triggerWords: [String]       // 触发词列表
    var triggerScope: TriggerScope   // 触发范围
    var triggerSound: TriggerSound   // 触发音效

    func addTriggerWord(_ word: String) -> Bool
    func removeTriggerWord(_ word: String) -> Bool
    func onSettingsChanged(_ callback: @escaping () -> Void) -> Cancellable
}
```

**存储键：**
- `voiceenter.enabled`
- `voiceenter.triggerWords`
- `voiceenter.triggerScope`
- `voiceenter.triggerSound`

---

## 4. 数据流

### 4.1 关键词触发流程

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
│              删除 2 个字符 + 播放音效 + 回车                      │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        消息发送                                  │
│                    "你好，帮我查天气"                             │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 表情触发流程

```
┌─────────────────────────────────────────────────────────────────┐
│                      摄像头采集帧                                 │
│                       (15fps)                                   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   VNDetectFaceLandmarks                         │
│                   检测 76 个面部关键点                            │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      侧脸过滤检查                                 │
│               faceAspectRatio < 0.5 → 跳过                       │
└─────────────────────────────────────────────────────────────────┘
                               │ 正脸
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ExpressionAnalyzer                            │
│              计算各表情系数 (0.0 ~ 1.0)                          │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      阈值检查                                    │
│              coefficient > threshold ?                          │
└─────────────────────────────────────────────────────────────────┘
                               │ 是
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    持续时间检查                                  │
│              duration >= minDuration ?                          │
└─────────────────────────────────────────────────────────────────┘
                               │ 是
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     冷却时间检查                                 │
│              elapsed >= cooldown ?                              │
└─────────────────────────────────────────────────────────────────┘
                               │ 是
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        触发！                                    │
│              播放音效 + 模拟回车键                               │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 设置变更流程

```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   UI 操作   │────▶│  AppState       │────▶│ SettingsManager │
│ (Toggle等)  │     │                 │     │                 │
└─────────────┘     └─────────────────┘     └─────────────────┘
                                                    │
                                                    ▼
                           ┌─────────────────────────────────┐
                           │          UserDefaults           │
                           │           持久化存储             │
                           └─────────────────────────────────┘
                                                    │
                                                    ▼ 通知回调
┌─────────────────────────────────────────────────────────────────┐
│                       监听器更新                                 │
│  - TextMonitor 检查 triggerScope                                │
│  - TerminalMonitor 检查 triggerScope                            │
│  - KittyMonitor 更新 triggerWords                               │
│  - FaceMonitor 更新 threshold/expression/sound                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. UI 架构

### 5.1 视图层级

```
VoiceEnterApp (@main)
├── AppDelegate
│   ├── NSStatusBar (菜单栏图标)
│   └── NSPopover
│       └── MenuBarView (主界面)
│           ├── headerSection (标题 + 状态指示)
│           ├── keywordTriggerCard (关键词触发)
│           │   ├── Toggle (启用开关)
│           │   ├── Picker (触发范围)
│           │   ├── FlowLayout (触发词标签)
│           │   ├── TextField (添加触发词)
│           │   └── 最近触发显示
│           ├── expressionTriggerCard (表情触发)
│           │   ├── Toggle (启用开关)
│           │   ├── Picker (表情类型)
│           │   ├── Slider (灵敏度)
│           │   ├── ProgressBar (检测值)
│           │   └── 使用提示
│           └── footerSection (底部控制)
│               ├── Picker (触发音效)
│               ├── Picker (主题模式)
│               └── Buttons (开始/停止/退出)
└── Settings (设置窗口)
    └── SettingsView
```

### 5.2 状态管理

```swift
class AppState: ObservableObject {
    // 监听状态
    @Published var isMonitoring: Bool = false
    @Published var isEnabled: Bool = true

    // 关键词设置
    @Published var triggerWords: [String] = []
    @Published var triggerScope: TriggerScope = .kittyOnly
    @Published var lastTriggered: String = ""

    // 表情设置
    @Published var isFaceExpressionEnabled: Bool = true
    @Published var selectedExpression: ExpressionType = .mouthOpen
    @Published var expressionThreshold: Float = 0.15
    @Published var hasFaceDetected: Bool = false
    @Published var currentExpressionValue: Float = 0

    // 外观设置
    @Published var themeMode: ThemeMode = .system
    @Published var triggerSound: TriggerSound = .tink

    // 核心组件
    let inputMonitor: UniversalInputMonitor
    let settingsManager: SettingsManager
}
```

### 5.3 主题系统

```swift
struct ThemeColors {
    let background: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    let accentGradient: LinearGradient
    let success: Color
    let warning: Color
    let danger: Color
    let border: Color
    let inputBackground: Color
    let inputText: Color

    static func colors(for colorScheme: ColorScheme) -> ThemeColors
}

enum ThemeMode: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
}
```

---

## 6. 错误处理与降级策略

### 6.1 错误类型与处理

| 错误场景 | 处理方式 |
|---------|---------|
| 辅助功能权限缺失 | 提示用户授权，继续其他监听器 |
| Kitty 未运行 | 跳过 KittyMonitor，不报错 |
| Terminal 未运行 | 跳过 TerminalMonitor，不报错 |
| 摄像头权限缺失 | 显示授权按钮，跳过 FaceMonitor |
| 无摄像头设备 | 显示提示（可用 iPhone 连续互通） |
| 按键模拟失败 | 记录日志，不中断 |

### 6.2 监听器降级优先级

```
优先级高 ──────────────────────────────────────▶ 优先级低

KittyMonitor ──▶ TerminalMonitor ──▶ TextMonitor ──▶ FaceMonitor
   (最稳定)       (需要 AppleScript)   (需要权限)      (需要摄像头)
```

---

## 7. 测试策略

### 7.1 测试覆盖

| 类型 | 数量 | 覆盖范围 |
|------|------|---------|
| 单元测试 | 62 个 | TriggerWordDetector, SettingsManager, KeySimulator, InputMonitor |
| 集成测试 | - | KeySimulator (需权限环境) |
| 手动测试 | - | 完整用户流程 |

### 7.2 测试用例示例

```swift
// 触发词检测测试
func testDetectChineseTriggerWord() {
    let detector = TriggerWordDetector(triggerWords: ["发送"])
    let result = detector.detect(in: "你好发送")
    XCTAssertEqual(result?.triggerWord, "发送")
    XCTAssertEqual(result?.contentWithoutTrigger, "你好")
}

func testDetectEnglishCaseInsensitive() {
    let detector = TriggerWordDetector(triggerWords: ["Go"])
    let result = detector.detect(in: "hello GO")
    XCTAssertEqual(result?.triggerWord, "GO")
}

func testIgnorePunctuation() {
    let detector = TriggerWordDetector(triggerWords: ["发送"])
    let result = detector.detect(in: "你好发送。")
    XCTAssertNotNil(result)  // 应该匹配
}

// 设置管理测试
func testAddDuplicateTriggerWord() {
    let manager = SettingsManager()
    _ = manager.addTriggerWord("Go")
    XCTAssertFalse(manager.addTriggerWord("go"))  // 不区分大小写
}

func testCannotRemoveLastTriggerWord() {
    let manager = SettingsManager()
    manager.resetToDefault()  // ["发送", "Go"]
    _ = manager.removeTriggerWord("发送")
    XCTAssertFalse(manager.removeTriggerWord("Go"))  // 不能删除最后一个
}
```

---

## 8. 性能优化

### 8.1 CPU 优化

| 优化措施 | 效果 |
|---------|------|
| 文本轮询间隔 0.15-0.2s | 平衡响应速度和 CPU 占用 |
| 防抖处理 0.5-0.6s | 减少不必要的检测计算 |
| 文本变化检测 | 内容无变化时跳过处理 |
| 按需启动监听器 | 不需要的监听器不启动 |
| 摄像头 15fps | 比默认 30fps 省电 50% |

### 8.2 内存优化

| 优化措施 | 效果 |
|---------|------|
| 弱引用回调 | 避免循环引用 |
| 及时清理 Timer | 停止时释放资源 |
| 不缓存终端内容 | 只保留最后一次文本 |
| 图像不存储 | 只处理实时帧 |

### 8.3 资源占用指标

| 指标 | 目标 | 实际 |
|------|------|------|
| CPU (空闲) | < 1% | ✅ |
| CPU (监听中) | < 5% | ✅ |
| 内存占用 | < 50MB | ✅ |
| 响应延迟 | < 200ms | ✅ |

---

## 9. 日志系统

### 9.1 日志格式

```
[ISO8601时间] [模块] 消息
```

### 9.2 日志示例

```
[2025-12-29T18:50:04Z] [UniversalMonitor] 启动通用输入监听器
[2025-12-29T18:50:04Z] [KittyMonitor] 开始监听 kitty 终端，触发词: ["发送", "Go"]
[2025-12-29T18:50:04Z] [FaceMonitor] 开始监听面部表情，触发表情: 张嘴，阈值: 0.15
[2025-12-29T18:50:13Z] [KittyMonitor] 输入行变化: '' -> '你好发送'
[2025-12-29T18:50:13Z] [KittyMonitor] ✅ 检测到触发词 '发送'，删除 2 个字符后回车
[2025-12-29T18:51:25Z] [FaceMonitor] ✅ 检测到 张嘴，系数: 0.45，触发回车
[2025-12-29T18:51:25Z] [FaceMonitor] 播放触发音效: Tink
```

### 9.3 日志位置

```
/tmp/voiceenter.log
```

查看实时日志：
```bash
tail -f /tmp/voiceenter.log
```

---

## 10. 扩展性设计

### 10.1 添加新监听器

1. 创建新的 Monitor 类，实现监听逻辑
2. 添加到 `UniversalInputMonitor` 的监听器列表
3. 在 `TriggerScope` 中添加对应选项（可选）
4. 更新 UI 添加配置选项（可选）

### 10.2 添加新表情类型

1. 在 `ExpressionType` 枚举中添加新类型
2. 实现对应的计算方法 `calculateXxx()`
3. 在 `analyzeExpression()` 中调用新方法
4. UI 自动适配（使用 `CaseIterable`）

### 10.3 添加新触发动作

当前只支持"删除 + 回车"，未来可扩展：
- 删除 + 粘贴
- 删除 + 自定义快捷键
- 执行自定义脚本
- 发送系统通知

---

## 附录

### A. 相关文档

- [PRD.md](./PRD.md) - 产品需求文档
- [FaceExpressionMonitor-Design.md](./FaceExpressionMonitor-Design.md) - 表情监听技术方案

### B. 参考资料

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/accessibility)
- [Kitty Remote Control](https://sw.kovidgoyal.net/kitty/remote-control/)
- [CGEvent Reference](https://developer.apple.com/documentation/coregraphics/cgevent)
- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [AVFoundation Camera](https://developer.apple.com/documentation/avfoundation/capture_setup)

### C. 更新历史

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| 1.0 | 2024-12 | 初始版本，关键词触发架构 |
| 1.1 | 2025-12 | 添加 FaceExpressionMonitor、音效系统、主题系统 |
