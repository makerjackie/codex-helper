# Codex Helper

[English](README.md) · [工作原理](docs/how-it-works.zh-CN.md) · [发布流程](docs/releasing.md) · [MIT License](LICENSE)

<p align="center">
  <img src="assets/app-icon-source.png" width="180" alt="Codex Helper 图标">
</p>

一个非官方、开源的 macOS 菜单栏辅助工具，逐步加入让 Codex 更可靠、更顺手的小功能。**自动重试**是第一个功能。

> 本项目与 OpenAI 无隶属或背书关系。

## 下载安装

从 [GitHub Releases](https://github.com/makerjackie/codex-helper/releases) 下载已经过 Developer ID 签名和 Apple 公证的 DMG，把 **Codex Helper** 拖入“应用程序”后打开一次即可。

要求：macOS 13+ 和 Codex 桌面版。

首次启动时，请在 **系统设置 → 隐私与安全性 → 辅助功能** 中允许 **Codex Helper**。它是一个独立 App，需要自己的权限来聚焦 Codex 输入框并提交续跑消息。如果你安装过此前的 Codex Auto Retry 原型，这次重命名同时改变了 App 名称、可执行文件、Bundle ID 和签名身份，因此 macOS 会把 Codex Helper 当成一个新 App，需要再授权一次。后续版本只要保持相同身份，正常更新通常不需要重新授权。

## 菜单栏和设置

点击菜单栏中的 Codex Helper 图标，可以：

- 开启或关闭“自动重试”；
- 选择自动、English 或简体中文；
- 开启或关闭登录时启动；
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
