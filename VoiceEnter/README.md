# VoiceEnter

<p align="center">
  <img src="docs/assets/icon.png" alt="VoiceEnter Logo" width="128" height="128">
</p>

<p align="center">
  <strong>🎤 语音输入自动回车助手 | Voice Input Auto-Enter Assistant</strong>
</p>

<p align="center">
  解放双手，用语音触发词自动发送消息
</p>

---

## 简介

VoiceEnter 是一款 macOS 菜单栏应用，专为语音输入场景设计。当你使用语音输入时，只需说出预设的触发词（如"发送"、"Go"），应用会自动删除触发词并按下回车键，实现完全免手操作的消息发送体验。

### 为什么需要 VoiceEnter？

使用 macOS 语音输入时，输入完内容后仍需要手动按回车发送，这打断了语音输入的流畅体验。VoiceEnter 通过监听触发词，让你可以：

- 🎯 **完全免手操作** - 说完内容，说"发送"，自动回车
- 🖥️ **多场景支持** - 支持 Kitty 终端、Terminal.app 和所有应用
- 😊 **表情触发** - 支持通过面部表情（如张嘴）触发回车
- ⚡ **低延迟** - 轮询检测，响应迅速

## 功能特性

### 核心功能

- **触发词检测** - 支持自定义多个触发词，中英文均可
- **自动回车** - 检测到触发词后，自动删除触发词并按下回车
- **多监听模式**
  - Kitty 终端监听（通过 `kitty @ get-text` API）
  - Terminal.app 监听（通过 AppleScript）
  - 通用应用监听（通过 Accessibility API）
  - 面部表情监听（通过 Vision 框架）

### 触发范围控制

- **仅 Kitty** - 只在 Kitty 终端中触发，避免在其他应用误触
- **仅终端** - 在 Kitty 和 Terminal.app 中触发
- **所有应用** - 在任何应用中触发（需辅助功能权限）

### 用户界面

- 精美的深色主题菜单栏界面
- 卡片式布局，信息层级清晰
- 实时状态显示
- 触发词标签管理

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15.0+ (仅编译时需要)
- Swift 5.9+

## 安装

### 从源码编译

```bash
# 克隆仓库
git clone https://github.com/your-username/VoiceEnter.git
cd VoiceEnter

# 编译 Release 版本
swift build -c release

# 运行
.build/release/VoiceEnter
```

### 权限配置

VoiceEnter 需要以下权限才能正常工作：

1. **辅助功能权限**（用于 TextMonitor）
   - 系统设置 → 隐私与安全性 → 辅助功能 → 添加 VoiceEnter

2. **摄像头权限**（用于面部表情检测，可选）
   - 首次使用时系统会提示授权

3. **Kitty 远程控制**（用于 Kitty 终端监听）
   - 在 `~/.config/kitty/kitty.conf` 中添加：
   ```
   allow_remote_control yes
   listen_on unix:/tmp/kitty
   ```

## 使用方法

### 基本使用

1. 启动 VoiceEnter，图标会出现在菜单栏
2. 点击菜单栏图标，确保"启用监听"开关已打开
3. 在支持的应用中使用语音输入
4. 说完内容后，说出触发词（默认："发送"或"Go"）
5. 应用会自动删除触发词并按下回车

### 自定义触发词

1. 点击菜单栏图标
2. 在"触发词"区域，点击 "+" 添加新触发词
3. 点击已有触发词的 "×" 可删除（至少保留一个）

### 调整触发范围

1. 点击菜单栏图标
2. 在"触发范围"下拉菜单中选择：
   - **仅 Kitty** - 最安全，只在 Kitty 中触发
   - **仅终端** - 在 Kitty 和 Terminal.app 中触发
   - **所有应用** - 在任何应用中触发

### 面部表情触发

1. 授予摄像头权限
2. 在设置中启用"表情触发"
3. 做出预设表情（如张嘴）即可触发回车

## 项目结构

```
VoiceEnter/
├── Package.swift                 # Swift Package 配置
├── Sources/
│   ├── VoiceEnterApp/           # 应用入口和 UI
│   │   └── VoiceEnterApp.swift  # SwiftUI 应用主文件
│   └── VoiceEnterCore/          # 核心业务逻辑
│       ├── UniversalInputMonitor.swift   # 统一输入监听器
│       ├── KittyTerminalMonitor.swift    # Kitty 终端监听
│       ├── TerminalAppMonitor.swift      # Terminal.app 监听
│       ├── TextMonitor.swift             # 通用文本监听
│       ├── FaceExpressionMonitor.swift   # 面部表情监听
│       ├── TriggerWordDetector.swift     # 触发词检测器
│       ├── KeySimulator.swift            # 按键模拟器
│       ├── SettingsManager.swift         # 设置管理器
│       └── Protocols.swift               # 协议定义
├── Tests/
│   └── VoiceEnterTests/         # 单元测试
└── docs/                        # 文档
    ├── PRD.md                   # 产品需求文档
    ├── Architecture.md          # 架构设计文档
    └── FaceExpressionMonitor-Design.md  # 表情监听设计
```

## 技术架构

### 监听器架构

```
┌─────────────────────────────────────────────────────────┐
│                  UniversalInputMonitor                   │
├─────────────────────────────────────────────────────────┤
│  TextMonitor          │ Accessibility API               │
│  KittyTerminalMonitor │ kitty @ get-text                │
│  TerminalAppMonitor   │ AppleScript                     │
│  FaceExpressionMonitor│ Vision + AVFoundation           │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                  TriggerWordDetector                     │
│          检测文本末尾是否包含触发词                        │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                     KeySimulator                         │
│          模拟键盘操作：删除触发词 + 回车                   │
└─────────────────────────────────────────────────────────┘
```

### 数据流

1. **输入监听** - 各 Monitor 轮询检测文本变化
2. **防抖处理** - 文本变化后等待 0.5-0.6 秒，避免频繁检测
3. **触发词检测** - TriggerWordDetector 检查文本末尾是否匹配触发词
4. **执行动作** - KeySimulator 删除触发词字符数 + 发送回车键

## 开发

### 运行测试

```bash
swift test
```

### 调试日志

应用运行时会输出日志到 `/tmp/voiceenter.log`：

```bash
tail -f /tmp/voiceenter.log
```

### 代码规范

- 遵循 Swift API Design Guidelines
- 使用中文注释，便于理解
- 测试优先开发（TDD）

## 常见问题

### Q: 为什么触发词没有生效？

A: 请检查以下几点：
1. 确保"启用监听"开关已打开
2. 检查触发范围设置是否正确
3. 对于非终端应用，需要授予辅助功能权限
4. 触发词必须在文本末尾才能生效

### Q: 如何避免误触发？

A: 建议：
1. 将触发范围设置为"仅 Kitty"或"仅终端"
2. 使用不常用的触发词
3. 触发词后可以加标点符号（如"发送。"）

### Q: Kitty 终端监听不工作？

A: 请确保 kitty.conf 中配置了：
```
allow_remote_control yes
listen_on unix:/tmp/kitty
```
配置后需要重启 Kitty。

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

---

<p align="center">
  Made with ❤️ for voice input enthusiasts
</p>
