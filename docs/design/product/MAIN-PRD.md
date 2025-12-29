# VoiceEnter - Main PRD

| 项目 | 内容 |
|------|------|
| 版本 | v1.1 |
| 作者 | VoiceEnter Team |
| 更新日期 | 2025-12-30 |

---

## 我们要解决什么问题？

使用 macOS 语音输入时，说完内容后必须手动按回车发送，打断了语音操作的流畅体验。
对于躺着编程、手被占用��或行动不便的用户，这个「最后一按」成为无法完全解放双手的障碍。

VoiceEnter 通过关键词触发和面部表情触发两种方式，让用户说完即发，实现真正的零手动操作。

---

## 为谁解决？

| 用户 | 痛点 |
|------|------|
| 语音输入开发者 | 与 AI 编程助手（Claude Code、Cursor）交互时，说完问题还要手动按回车 |
| 特殊姿势用户 | 躺着编程、站立办公、手被占用（吃东西、抱猫）时无法操作键盘 |
| 无障碍用户 | 行动不便，无法完全脱离键盘实现全语音操作 |

---

## 如何验证成功？

| 指标 | 目标 |
|------|------|
| 触发成功率 | > 95%（触发词/表情被正确识别的比例） |
| 误触发率 | < 1%（非预期触发的比例） |
| 响应延迟 | < 200ms（从检测到触发词到执行回车） |

---

## 核心功能

| 功能 | 解决什么问题 | 优先级 | Feature PRD |
|------|-------------|--------|-------------|
| 关键词触发 | 说出触发词（如「发送」）自动删除触发词并按回车，无需手动操作 | P0 | [FEATURE-keyword-trigger](./features/FEATURE-keyword-trigger.md) |
| 多场景监听 | 支持 Kitty、Terminal、通用应用，覆盖不同使用场景 | P0 | [FEATURE-multi-scene-monitor](./features/FEATURE-multi-scene-monitor.md) |
| 表情触发 | 不方便说话时，通过面部表情（张嘴、撅嘴等）触发回车 | P1 | [FEATURE-expression-trigger](./features/FEATURE-expression-trigger.md) |
| 触发范围控制 | 限制触发生效范围，避免在不需要的应用中误触发 | P1 | [FEATURE-trigger-scope](./features/FEATURE-trigger-scope.md) |
| 触发音效反馈 | 触发时播放音效，提供明确的操作反馈 | P2 | [FEATURE-trigger-sound](./features/FEATURE-trigger-sound.md) |
