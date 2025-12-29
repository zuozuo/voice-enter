# FEATURE-multi-scene-monitor

| 项目 | 内容 |
|------|------|
| 版本 | v1.1 |
| 作者 | VoiceEnter Team |
| 创建日期 | 2025-12-30 |
| 关联 | [MAIN-PRD](../MAIN-PRD.md) |

---

## 解决什么问题？

用户在不同应用中使用语音输入：终端（Kitty、Terminal.app）、浏览器、备忘录等。单一的监听方式无法覆盖所有场景。

通过实现多种监听器（Kitty API、AppleScript、Accessibility API），根据当前应用自动选择最合适的监听方式，确保触发词检测在各种场景下都能正常工作。

---

## 用户故事

| ID | 用户故事 | 优先级 | 验收标准 |
|----|----------|--------|----------|
| US-001 | 作为 Kitty 用户，我想在 Kitty 终端中使用触发词，以便与 Claude Code 交互时自动发送 | P0 | 在 Kitty 中输入触发词能正确触发 |
| US-002 | 作为 Terminal 用户，我想在 macOS 自带终端中使用触发词，以便兼容原生终端 | P1 | 在 Terminal.app 中输入触发词能正确触发 |
| US-003 | 作为通用用户，我想在任何应用中使用触发词，以便在浏览器、备忘录等应用中也能自动发送 | P1 | 在 Safari、备忘录等应用中输入触发词能正确触发 |

---

## 核心流程

```
+-----------------------------------------------------------------------+
|                      UniversalInputMonitor                             |
|                         (监听协调器)                                    |
+-----------------------------------------------------------------------+
        |                    |                    |
        v                    v                    v
+---------------+    +---------------+    +------------------+
| KittyTerminal |    | TerminalApp   |    |   TextMonitor    |
|   Monitor     |    |   Monitor     |    | (Accessibility)  |
+---------------+    +---------------+    +------------------+
        |                    |                    |
        v                    v                    v
  kitty @ get-text      AppleScript        AXUIElement API
        |                    |                    |
        +--------------------+--------------------+
                             |
                             v
                    +------------------+
                    | TriggerDetector  |
                    +------------------+
                             |
                             v
                    +------------------+
                    |   KeySimulator   |
                    +------------------+
```

---

## 监听器详情

### 1. KittyTerminalMonitor

| 属性 | 说明 |
|------|------|
| 技术方案 | `kitty @ get-text` 远程控制 API |
| 轮询间隔 | 0.15 秒 |
| 触发范围 | kittyOnly, terminalsOnly, allApps |
| 特殊处理 | 支持 Claude Code 模式（识别 `> ` 提示符） |
| 前置条件 | Kitty 需启用 `allow_remote_control yes` |

### 2. TerminalAppMonitor

| 属性 | 说明 |
|------|------|
| 技术方案 | AppleScript |
| 轮询间隔 | 0.2 秒 |
| 触发范围 | terminalsOnly, allApps |
| 特殊处理 | 获取前台窗口内容 |

### 3. TextMonitor

| 属性 | 说明 |
|------|------|
| 技术方案 | macOS Accessibility API |
| 轮询间隔 | 0.2 秒 |
| 触发范围 | allApps |
| 前置条件 | 需要辅助功能权限 |
| 适用场景 | 浏览器、备忘录、文本编辑器等 |

---

## 业务规则

| 规则 | 说明 |
|------|------|
| 启动策略 | 任一监听器启动成功即算成功 |
| 降级策略 | Kitty 未运行时自动跳过 KittyMonitor |
| 权限处理 | 辅助功能权限缺失时提示用户授权 |
| 并行监听 | 多个监听器可同时运行，互不干扰 |
| 去重处理 | 同一文本变化只触发一次 |

---

## 验收标准

| 场景 | 前置条件 | 操作步骤 | 预期结果 |
|------|----------|----------|----------|
| Kitty 监听 | Kitty 已启动 | 在 Kitty 中输入"测试发送" | 正确触发，删除"发送"并回车 |
| Terminal 监听 | Terminal.app 已启动 | 在 Terminal 中输入"测试发送" | 正确触发，删除"发送"并回车 |
| 通用应用监听 | 已授权辅助功能 | 在备忘录中输入"测试发送" | 正确触发，删除"发送"并回车 |
| 无 Kitty | Kitty 未安装 | 启动监听 | 其他监听器正常工作，无报错 |
| 无权限 | 未授权辅助功能 | 启动监听 | 提示授权，Kitty 监听仍可用 |

---

## 技术实现

### 核心组件

- `UniversalInputMonitor`：监听协调器
- `KittyTerminalMonitor`：Kitty 终端监听
- `TerminalAppMonitor`：Terminal.app 监听
- `TextMonitor`：通用应用监听（Accessibility API）

### 关键 API

```swift
// 启动所有监听器
func startMonitoring() -> Bool

// 停止所有监听器
func stopMonitoring()

// 检查辅助功能权限
func checkAccessibilityPermission() -> Bool
```
