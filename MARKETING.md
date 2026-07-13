# Launch copy / 宣传文案

## One-line description

**EN:** A tiny macOS helper that safely continues a Codex task when the selected model is temporarily at capacity.

**中文：** 一个轻量的 macOS 开源助手：Codex 模型暂时满载时，安全地让原任务自动继续。

## GitHub description

**EN:** Keep Codex tasks moving through temporary model-capacity errors. Native macOS, safe backoff, no duplicate turns.

**中文：** Codex 模型满载时自动续跑：原生 macOS、渐进退避、防重复回合。

## Short social post

### English

Codex stopped because the selected model was at capacity—again.

So I built **Codex Auto Retry**, a tiny open-source macOS helper that watches for that exact failure, waits with progressive backoff, checks that you have not already continued manually, and safely resumes the original task.

- No Codex patching
- No proxy or cloud service
- No project-file access
- English + 中文
- MIT licensed

GitHub: https://github.com/makerjackie/codex-auto-retry

### 中文

Codex 又因为“所选模型已满载”停住了，于是我做了一个小工具：**Codex 自动重试**。

它会识别这个特定错误，按渐进时间等待；重试前先确认你没有手动继续，再安全地回到原任务续跑。

- 不修改 Codex
- 不走代理或云服务
- 不读取项目文件
- 中英文支持
- MIT 开源

GitHub：https://github.com/makerjackie/codex-auto-retry

## Longer launch post

### English

Temporary model capacity should be a pause, not the end of an agent task.

**Codex Auto Retry** is a small native macOS agent for one frustrating edge case: `Selected model is at capacity. Please try a different model.` It tails the local Codex log, identifies the affected visible task, and schedules up to six retries with progressive backoff. Before every retry it checks the task session for newer user or turn activity, so it backs off if you already handled the problem yourself.

When safe, it opens the original Codex task, submits a localized continuation message, and restores the app you were using. There is no cloud backend, telemetry, project-file access, or Codex binary modification.

The project is deliberately small, auditable, bilingual, and MIT licensed.

### 中文

模型暂时满载，应该只是暂停，不应该直接终结一个正在执行的 Agent 任务。

**Codex 自动重试**专门解决这个烦人的边界情况：`Selected model is at capacity. Please try a different model.`。它会监听本地 Codex 日志，定位受影响的可见主任务，并按渐进退避最多安排 6 次重试。每次真正重试之前，它都会检查任务是否已经出现新的用户消息或新回合；如果你已经手动处理，它会自动让路。

确认安全后，它会打开原 Codex 任务，提交本地化续跑消息，再恢复你此前使用的 App。整个过程没有云端后端、没有遥测、不读取项目文件，也不修改 Codex 二进制。

项目刻意保持小巧、可审计、中英双语，并采用 MIT 协议开源。
