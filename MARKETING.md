# Codex Helper launch copy / 宣传文案

## One-line description

**EN:** An open-source macOS companion for Codex. See quota in a native widget or floating rail, and safely continue capacity-interrupted tasks.

**中文：** 一个开源的 Codex macOS 辅助工具：用原生小组件或悬浮轨道查看额度，并在模型满载时安全续跑原任务。

## GitHub description

**EN:** Auto Retry, account limits, official updates, and signed in-app updates for Codex on macOS.

**中文：** Codex macOS 菜单栏助手：自动重试、额度查看、官方动态和签名应用内更新。

## Short social post

### English

Codex stopped because the selected model was at capacity—again.

So I built **Codex Helper**. Auto Retry watches for that exact failure, waits with progressive backoff, checks that you have not already continued manually, and safely resumes the original task.

- No Codex patching
- No proxy or cloud service
- No project-file access
- English + 中文
- Built-in end-to-end test
- Native macOS widget + optional floating rail
- Official Codex updates + docs
- Signed in-app updates
- MIT licensed

GitHub: https://github.com/makerjackie/codex-helper

### 中文

Codex 又因为“所选模型已满载”停住了，于是我做了 **Codex Helper**。

它会识别这个特定错误，按渐进时间等待；重试前先确认你没有手动继续，再安全地回到原任务续跑。

- 不修改 Codex
- 不走代理或云服务
- 不读取项目文件
- 中英文支持
- 内置端到端验证
- 原生 macOS 小组件 + 可选悬浮轨道
- Codex 官方动态与文档入口
- 签名校验的应用内更新
- MIT 开源

GitHub：https://github.com/makerjackie/codex-helper

## Longer launch post

### English

Temporary model capacity should be a pause, not the end of an agent task.

**Codex Helper** is a native macOS menu bar companion. Auto Retry handles one frustrating edge case: `Selected model is at capacity. Please try a different model.` It tails the local Codex log, identifies the affected visible task, and schedules up to six retries with progressive backoff. Before every retry it checks the task session for newer user or turn activity, so it backs off if you already handled the problem yourself.

When safe, it opens the original Codex task, submits a localized continuation message, and restores the app you were using. A native macOS widget, menu bar item, and optional floating rail keep remaining quota visible. There is no cloud backend, telemetry, project-file access, or Codex binary modification.

The project is deliberately small, auditable, bilingual, and MIT licensed.

### 中文

模型暂时满载，应该只是暂停，不应该直接终结一个正在执行的 Agent 任务。

**Codex Helper** 会处理这个烦人的边界情况：`Selected model is at capacity. Please try a different model.`。它会监听本地 Codex 日志，定位受影响的可见主任务，并按渐进退避最多安排 6 次重试。每次真正重试之前，它都会检查任务是否已经出现新的用户消息或新回合；如果你已经手动处理，它会自动让路。

确认安全后，它会打开原 Codex 任务，提交本地化续跑消息，再恢复你此前使用的 App。原生 macOS 小组件、菜单栏和可选悬浮轨道都能显示剩余额度与重置时间。整个过程没有云端后端、没有遥测、不读取项目文件，也不修改 Codex 二进制。

项目刻意保持小巧、可审计、中英双语，并采用 MIT 协议开源。
