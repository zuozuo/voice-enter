# VoiceEnter

语音输入后自动回车，解放双手的编程体验。

## 问题

使用语音输入与 AI 编程助手（Claude Code、Cursor、Copilot Chat）交流时，每次说完都需要手动按回车发送。这个小动作打断了流畅的体验，特别是：

- 躺着编程
- 站立办公、边踱步边思考
- 手被占用（吃东西、抱猫、抱娃）
- 手部不便
- 就是懒，不想动

## 解决方案

### 方案 A：软件（开发中）

macOS 菜单栏工具，检测语音输入的触发词（如"发送"、"Go"），自动删除触发词并按回车。

### 方案 B：硬件（原型验证中）

蓝牙小遥控器，按一下发送回车键。基于 ESP32-C3，即插即用，不需要任何驱动。

## 快速开始

### 系统要求

- macOS 12.0+
- Xcode 15.0+ (用于编译)
- 辅助功能权限 (用于模拟按键)

### 构建项目

```bash
cd VoiceEnter
swift build
```

### 运行测试

```bash
cd VoiceEnter
swift test
```

测试覆盖 62 个用例，包括：
- 触发词检测（中英文、大小写、边界情况）
- 设置管理（持久化、触发词增删）
- 按键模拟（回车、删除、组合操作）
- 输入监听（防抖、状态管理）

### 运行应用（开发中）

```bash
cd VoiceEnter
swift run
```

> ⚠️ **注意**：当前版本核心模块已完成，但完整的 macOS 菜单栏应用还在开发中。运行后会显示 "VoiceEnter - 语音输入自动回车"。

## 开发状态

### 已完成

- [x] 产品设计文档
- [x] 核心模块 TDD 开发
  - [x] TriggerWordDetector - 触发词检测器
  - [x] SettingsManager - 设置管理器
  - [x] KeySimulator - 按键模拟器
  - [x] InputMonitor - 输入监听器
- [x] 62 个单元测试全部通过

### 进行中

- [ ] 系统输入监听集成 (CGEventTap)
- [ ] SwiftUI 菜单栏界面
- [ ] 辅助功能权限请求

### 计划中

- [ ] 应用图标设计
- [ ] DMG 打包分发
- [ ] 开机自启动
- [ ] 硬件方案原型

## 项目结构

```
VoiceEnter/
├── Package.swift              # Swift Package 配置
├── Sources/
│   ├── VoiceEnterApp/         # 应用入口
│   │   └── main.swift
│   └── VoiceEnterCore/        # 核心库
│       ├── Protocols.swift    # 协议定义
│       ├── TriggerWordDetector.swift
│       ├── SettingsManager.swift
│       ├── KeySimulator.swift
│       └── InputMonitor.swift
└── Tests/
    └── VoiceEnterTests/       # 单元测试
        ├── TriggerWordDetectorTests.swift
        ├── SettingsManagerTests.swift
        ├── KeySimulatorTests.swift
        └── InputMonitorTests.swift
```

## 工作原理

1. **输入监听**：通过 macOS CGEventTap 监听系统键盘输入
2. **触发词检测**：检测输入是否以触发词结尾（如 "发送"、"Go"）
3. **防抖处理**：300ms 延迟，避免输入过程中误触发
4. **按键模拟**：检测到触发词后，删除触发词并模拟回车键

## 默认触发词

- `发送` - 中文触发词
- `Go` - 英文触发词（不区分大小写）

触发词可自定义，最多 10 个字符。

## 文档

- [产品设计文档](docs/plans/2025-12-29-voice-enter-design.md)
- [功能 PRD](docs/design/product/features/FEATURE-voice-trigger-v1.md)

## 技术栈

- **语言**：Swift 5.9
- **框架**：SwiftUI, CoreGraphics
- **开发方式**：TDD (测试驱动开发)
- **包管理**：Swift Package Manager

## License

MIT
