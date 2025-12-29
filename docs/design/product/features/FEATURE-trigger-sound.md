# FEATURE-trigger-sound

| 项目 | 内容 |
|------|------|
| 版本 | v1.1 |
| 作者 | VoiceEnter Team |
| 创建日期 | 2025-12-30 |
| 关联 | [MAIN-PRD](../MAIN-PRD.md) |

---

## 解决什么问题？

用户触发后没有明确的反馈，不确定系统是否已经响应了操作。尤其在语音输入场景，用户注意力可能不在屏幕上。

通过在触发时播放音效，给用户提供即时的听觉反馈，确认操作已被识别和执行，提升使用体验和信心。

---

## 用户故事

| ID | 用户故事 | 优先级 | 验收标准 |
|----|----------|--------|----------|
| US-001 | 作为用户，我想在触发时听到提示音，以便确认系统已响应 | P0 | 触发后播放音效 |
| US-002 | 作为用户，我想选择喜欢的音效，以便获得个性化体验 | P1 | 支持 13 种系统音效可选 |
| US-003 | 作为安静环境用户，我想关闭音效，以便不打扰他人 | P0 | 支持"无"选项关闭音效 |
| US-004 | 作为用户，我想在选择音效时预览，以便知道它听起来怎样 | P2 | 选择时自动播放预览 |

---

## 核心流程

```
+------------------+
|  触发成功        |
| (关键词/表情)    |
+------------------+
        |
        v
+------------------+     是
| 音效设置为"无"？ | ---------> 不播放
+------------------+
        | 否
        v
+------------------+
| 获取系统音效名称  |
+------------------+
        |
        v
+------------------+     失败
| NSSound 播放     | ---------> NSSound.beep() 备用
+------------------+
        | 成功
        v
+------------------+
|   音效播放完成   |
+------------------+
```

---

## 支持的音效

| 音效名称 | 标识符 | 说明 |
|----------|--------|------|
| 无 | none | 不播放音效 |
| Tink | tink | 清脆的敲击声（**默认**） |
| Pop | pop | 气泡弹出声 |
| Ping | ping | 清脆的铃声 |
| Glass | glass | 玻璃碰撞声 |
| Blow | blow | 吹气声 |
| Bottle | bottle | 瓶子声 |
| Frog | frog | 青蛙叫声 |
| Funk | funk | 低沉的提示音 |
| Morse | morse | 莫尔斯电码声 |
| Purr | purr | 猫咪呼噜声 |
| Sosumi | sosumi | 经典 Mac 音效 |
| Submarine | submarine | 潜水艇声 |
| Hero | hero | 英雄登场音效 |

---

## 业务规则

| 规则 | 说明 |
|------|------|
| 默认音效 | Tink（清脆不刺耳） |
| 音效来源 | macOS 系统音效（NSSound） |
| 备用机制 | 如果系统音效不可用，使用 NSSound.beep() |
| 触发时机 | 关键词触发和表情触发都会播放 |
| 全局设置 | 一个音效设置同时应用于所有触发方式 |
| 预览功能 | 选择音效时自动播放一次 |
| 持久化存储 | 使用 UserDefaults 存储设置 |

---

## 验收标准

| 场景 | 前置条件 | 操作步骤 | 预期结果 |
|------|----------|----------|----------|
| 关键词触发音效 | 音效设为 Tink | 输入触发词 | 播放 Tink 音效 |
| 表情触发音效 | 音效设为 Pop | 张嘴触发 | 播放 Pop 音效 |
| 关闭音效 | 音效设为"无" | 输入触发词 | 不播放音效 |
| 音效预览 | 在设置菜单 | 选择 Glass | 立即播放 Glass 预览 |
| 切换音效 | 当前 Tink | 切换到 Ping | 下次触发播放 Ping |
| 持久化 | 设置某音效后退出 | 重新启动应用 | 保持之前的选择 |
| 备用音效 | 系统音效不可用 | 触发 | 播放系统 beep 音 |

---

## 技术实现

### 核心组件

- `TriggerSound`：音效枚举
- `SettingsManager`：音效配置存储
- `NSSound`：macOS 系统音效播放

### 关键 API

```swift
/// 触发音效
public enum TriggerSound: String, CaseIterable, Codable {
    case none = "无"
    case tink = "Tink"
    case pop = "Pop"
    // ... 更多音效

    /// 系统音效名称（用于 NSSound）
    public var systemName: String? {
        switch self {
        case .none: return nil
        default: return rawValue
        }
    }
}

/// 获取/设置触发音效
var triggerSound: TriggerSound { get set }
```

### 播放逻辑

```swift
/// 播放触发音效
private func playTriggerSound() {
    let sound = settingsManager.triggerSound

    // 如果设置为"无"，不播放
    guard let soundName = sound.systemName else {
        return
    }

    // 播放系统音效
    if let nsSound = NSSound(named: soundName) {
        nsSound.play()
    } else {
        // 备用：使用系统提示音
        NSSound.beep()
    }
}
```

---

## UI 设计

### 菜单栏设置

```
触发音效 [下拉菜单]
├── 无
├── Tink ✓ (默认)
├── Pop
├── Ping
├── Glass
├── Blow
├── Bottle
├── Frog
├── Funk
├── Morse
├── Purr
├── Sosumi
├── Submarine
└── Hero
```

### 交互

- 选择后立即播放预览
- 选择后设置自动保存
- 当前选中项显示勾选标记

---

## 配置选项

| 配置项 | 默认值 | 存储键 | 说明 |
|--------|--------|--------|------|
| triggerSound | tink | voiceenter.triggerSound | 触发音效 |
