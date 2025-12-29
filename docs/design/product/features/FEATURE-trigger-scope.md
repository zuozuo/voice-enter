# FEATURE-trigger-scope

| 项目 | 内容 |
|------|------|
| 版本 | v1.1 |
| 作者 | VoiceEnter Team |
| 创建日期 | 2025-12-30 |
| 关联 | [MAIN-PRD](../MAIN-PRD.md) |

---

## 解决什么问题？

用户担心触发词在所有应用中生效会导致误触发，例如在浏览器中输入包含"发送"的内容时被意外触发。

通过提供触发范围控制，让用户可以选择触发词只在特定类型的应用中生效（如仅终端），在保证功能可用性的同时最大限度减少误触发风险。

---

## 用户故事

| ID | 用户故事 | 优先级 | 验收标准 |
|----|----------|--------|----------|
| US-001 | 作为 Kitty 用户，我想让触发词只在 Kitty 中生效，以便专注使用 Claude Code | P0 | 选择"仅 Kitty"后，其他应用不触发 |
| US-002 | 作为终端用户，我想让触发词在所有终端中生效，以便兼容 Terminal.app | P1 | 选择"仅终端"后，Kitty 和 Terminal.app 都能触发 |
| US-003 | 作为全能用户，我想在任何应用中使用触发词，以便获得完整的语音输入体验 | P1 | 选择"所有应用"后，浏览器、备忘录等都能触发 |
| US-004 | 作为用户，我想随时切换触发范围，以便适应不同的使用场景 | P0 | 切换后立即生效，无需重启 |

---

## 核心流程

```
+------------------+
| 用户选择触发范围  |
+------------------+
        |
        v
+------------------+
| 保存到 Settings  |
+------------------+
        |
        +--------------------+--------------------+
        |                    |                    |
        v                    v                    v
+---------------+    +---------------+    +------------------+
|  仅 Kitty     |    |  仅终端       |    |   所有应用       |
+---------------+    +---------------+    +------------------+
        |                    |                    |
        v                    v                    v
   Kitty 启用           Kitty 启用           Kitty 启用
                       Terminal 启用        Terminal 启用
                                            TextMonitor 启用
```

---

## 范围选项

| 范围 | 标识符 | 说明 | 启用的监听器 |
|------|--------|------|--------------|
| 仅 Kitty | kittyOnly | 只在 Kitty 终端中触发 | KittyTerminalMonitor |
| 仅终端 | terminalsOnly | 在 Kitty 和 Terminal.app 中触发 | KittyTerminalMonitor, TerminalAppMonitor |
| 所有应用 | allApps | 在所有应用中触发 | KittyTerminalMonitor, TerminalAppMonitor, TextMonitor |

---

## 业务规则

| 规则 | 说明 |
|------|------|
| 默认范围 | kittyOnly（最安全） |
| 即时生效 | 切换后立即生效，无需重启 |
| 监听器控制 | 各监听器根据范围自动判断是否处理 |
| 表情触发独立 | 触发范围不影响表情触发（表情触发全局有效） |
| 持久化存储 | 使用 UserDefaults 存储设置 |

### 监听器行为

| 监听器 | kittyOnly | terminalsOnly | allApps |
|--------|-----------|---------------|---------|
| KittyTerminalMonitor | ✅ 启用 | ✅ 启用 | ✅ 启用 |
| TerminalAppMonitor | ❌ 跳过 | ✅ 启用 | ✅ 启用 |
| TextMonitor | ❌ 跳过 | ❌ 跳过 | ✅ 启用 |

---

## 验收标准

| 场景 | 前置条件 | 操作步骤 | 预期结果 |
|------|----------|----------|----------|
| 仅 Kitty | 选择"仅 Kitty" | 在 Kitty 中输入触发词 | 正确触发 |
| 仅 Kitty 排除 | 选择"仅 Kitty" | 在 Terminal.app 中输入触发词 | 不触发 |
| 仅终端 | 选择"仅终端" | 在 Terminal.app 中输入触发词 | 正确触发 |
| 仅终端排除 | 选择"仅终端" | 在备忘录中输入触发词 | 不触发 |
| 所有应用 | 选择"所有应用" | 在备忘录中输入触发词 | 正确触发 |
| 即时切换 | 当前"仅 Kitty" | 切换到"所有应用" | 立即生效，无需重启 |
| 持久化 | 选择某范围后退出 | 重新启动应用 | 保持之前的选择 |

---

## 技术实现

### 核心组件

- `TriggerScope`：触发范围枚举
- `SettingsManager`：范围配置存储
- 各 Monitor：根据范围自动判断是否处理

### 关键 API

```swift
/// 触发范围
public enum TriggerScope: Int, CaseIterable, Codable {
    case kittyOnly = 0      // 仅 Kitty 终端
    case terminalsOnly = 1  // Kitty + Terminal.app
    case allApps = 2        // 所有应用

    var displayName: String { ... }
    var description: String { ... }
}

/// 获取/设置触发范围
var triggerScope: TriggerScope { get set }
```

### 监听器内部逻辑

```swift
// TextMonitor - 只在 allApps 模式下工作
guard settingsManager.triggerScope == .allApps else { return }

// TerminalAppMonitor - 在 terminalsOnly 和 allApps 模式下工作
guard settingsManager.triggerScope != .kittyOnly else { return }

// KittyTerminalMonitor - 始终启用（在所有范围中都工作）
// 无需额外判断
```

---

## UI 设计

### 菜单栏设置

```
触发范围 [下拉菜单]
├── 仅 Kitty     ← 只在 Kitty 终端中触发
├── 仅终端       ← 在 Kitty 和 Terminal.app 中触发
└── 所有应用     ← 在所有应用中触发（包括浏览器、备忘录等）
```

### 设置面板

- 分段控件（Picker）显示三个选项
- 下方显示当前选项的详细描述
- 切换后即时保存

---

## 配置选项

| 配置项 | 默认值 | 存储键 | 说明 |
|--------|--------|--------|------|
| triggerScope | kittyOnly (0) | voiceenter.triggerScope | 触发范围 |
