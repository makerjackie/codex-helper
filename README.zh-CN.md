# Codex Helper

[English](README.md) · [工作原理](docs/how-it-works.zh-CN.md) · [发布流程](docs/releasing.md) · [MIT License](LICENSE)

<p align="center">
  <img src="assets/app-icon-source.png" width="180" alt="Codex Helper 图标">
</p>

一个非官方、开源的 Codex macOS 菜单栏辅助工具：安全自动重试、额度查看、官方动态与文档，以及经过签名校验的应用内更新。

> 本项目与 OpenAI 无隶属或背书关系。

## 下载安装

从 [GitHub Releases](https://github.com/makerjackie/codex-helper/releases) 下载已经过 Developer ID 签名和 Apple 公证的 DMG，把 **Codex Helper** 拖入“应用程序”后打开一次即可。

要求：macOS 13+ 和 Codex 桌面版。

首次启动时，请在 **系统设置 → 隐私与安全性 → 辅助功能** 中允许 **Codex Helper**。它是一个独立 App，需要自己的权限来聚焦 Codex 输入框并提交续跑消息。如果你安装过此前的 Codex Auto Retry 原型，这次重命名同时改变了 App 名称、可执行文件、Bundle ID 和签名身份，因此 macOS 会把 Codex Helper 当成一个新 App，需要再授权一次。后续版本只要保持相同身份，正常更新通常不需要重新授权。

## 菜单栏和设置

点击菜单栏中的 Codex Helper 图标，可以：

- 开启或关闭“自动重试”；
- 查看 Codex 额度使用比例、重置时间和可用重置次数；
- 选择自动、English 或简体中文；
- 开启或关闭登录时启动；
- 自动检查并下载经过签名的 Codex Helper 更新；
- 对自己选择的任务运行安全的自动重试端到端测试；
- 阅读 Codex 官方更新日志和 OpenAI News 中与 Codex 有关的动态；
- 打开 Codex 文档、命令参考、故障排查和 Tibo 的 X 主页；
- 打开设置、辅助功能设置或日志；
- 完全退出 Codex Helper。

也可以使用 Spotlight 搜索 **Codex Helper**。App 已经运行时再次打开，会直接显示设置窗口。

## 自动重试功能

当 Codex 出现：

```text
Selected model is at capacity. Please try a different model.
```

Codex Helper 会：

1. 监听 `~/.codex/log/codex-tui.log`，提取受影响的任务 ID。
2. 只处理可见主任务，忽略隐藏子代理。
3. 按 `8 / 20 / 45 / 90 / 180 / 300` 秒渐进退避，最多重试 6 次。
4. 如果你已经发消息或新回合已经开始，自动取消重试。
5. 打开原 Codex 任务，在 Codex 内提交本地化续跑消息，再恢复此前使用的 App。

它不会修改 Codex、代理网络请求、读取项目文件或保存对话内容。它重试的是同一个任务，不会自动切换模型。

## 额度使用情况

“额度使用”子菜单通过官方本地 Codex App Server 的 `account/rateLimits/read` 读取数据，显示各额度窗口的已使用比例、重置时间，以及存在时的可用重置次数。Codex Helper 复用 Codex 自己管理的登录状态，不会直接读取 `~/.codex/auth.json` 中的令牌。

## 自动更新

自动更新默认开启。Codex Helper 每天最多检查一次最新 GitHub Release；发现新版本后在后台下载 DMG。真正安装仍需要点击明确可见的“安装并重启”，不会在工作过程中突然退出。

替换 App 前会依次验证发布的 SHA-256、Developer ID Bundle ID、Team ID 和 Gatekeeper 结果。如果 App 所在位置不可写，当前版本保持不变，并提示无法自动安装。

## 不等真实故障也能验证

在菜单栏选择 **测试自动重试…**，选择一个处于空闲状态、输入框里没有草稿的最近 Codex 任务并确认。Codex Helper 会生成一条带有该任务 ID 的模拟容量错误，交给正式匹配器和可见任务检查处理；3 秒后再次检查新活动，再打开任务并提交一条明确标记的测试消息。看到包含 **Codex Helper 测试通过** 的回复，就证明整条任务定位与 GUI 控制链路能在你当前安装的 Codex 版本上工作。

真实故障发生时，Codex 日志会在精确的容量错误旁写入 `thread_id=<UUID>`。Codex Helper 会用 `~/.codex/session_index.jsonl` 验证该 UUID，退避等待，重试前检查任务是否已经有新活动，然后打开 `codex://threads/<UUID>`。只有辅助功能确认 Codex 位于前台、当前聚焦控件是空白文本输入区时才会提交；提交后还会检查目标任务 session 是否收到了该消息。

## 最新动态和了解 Codex

菜单读取公开的 [Codex Changelog RSS](https://learn.chatgpt.com/docs/changelog/rss.xml) 与 [OpenAI News RSS](https://openai.com/news/rss.xml)，后者只保留与 Codex 有关的内容。结果会缓存在本地；成功来源每 6 小时刷新一次，失败后至少退避 15 分钟。Tibo 项只是普通浏览器链接，不会抓取 X 时间线。

## 从源码安装

```bash
git clone https://github.com/makerjackie/codex-helper.git
cd codex-helper
./install.sh
```

源码构建采用本机 ad-hoc 签名，重新构建后可能需要再次授予辅助功能权限。日常使用建议优先下载 Developer ID 签名的 Release 版本。

## 测试

```bash
./test.sh
```

## 开源协议

[MIT](LICENSE)
