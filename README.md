# Codex Helper

[简体中文](README.zh-CN.md) · [How it works](docs/how-it-works.md) · [Releasing](docs/releasing.md) · [MIT License](LICENSE)

<p align="center">
  <img src="assets/app-icon-source.png" width="180" alt="Codex Helper icon">
</p>

An unofficial, open-source macOS menu bar companion for small utilities that make Codex more reliable. **Auto Retry** is its first feature.

> Not affiliated with or endorsed by OpenAI.

## Download

Download the signed and Apple-notarized DMG from [GitHub Releases](https://github.com/makerjackie/codex-helper/releases), drag **Codex Helper** into Applications, and open it once.

Requirements: macOS 13+ and the Codex desktop app.

On first launch, allow **Codex Helper** in **System Settings → Privacy & Security → Accessibility**. Codex Helper needs its own permission because it is a separate app that focuses the Codex composer and submits the continuation message. If you used the earlier Codex Auto Retry prototype, this rename changes the app name, executable, bundle ID, and signing identity, so macOS treats Codex Helper as a new app and asks once more. Developer ID-signed updates with the same identity should not normally require permission again.

## Menu bar and settings

Click the Codex Helper menu bar icon to:

- turn Auto Retry on or off;
- choose Automatic, English, or Simplified Chinese;
- enable or disable Launch at Login;
- open Settings, Accessibility Settings, or logs;
- quit Codex Helper completely.

You can also search for **Codex Helper** in Spotlight. Opening it again brings up the Settings window.

## Auto Retry

When Codex reports:

```text
Selected model is at capacity. Please try a different model.
```

Codex Helper:

1. Watches `~/.codex/log/codex-tui.log` and extracts the affected task ID.
2. Handles only visible root tasks and ignores hidden subagents.
3. Retries after `8 / 20 / 45 / 90 / 180 / 300` seconds, up to six times.
4. Cancels if you already sent a message or a new turn started.
5. Opens the original Codex task, submits a localized continuation prompt inside Codex, and restores the app you were using.

It does not modify Codex, proxy network traffic, read project files, or store conversation content. It retries the same task; it does not automatically switch models.

## Build from source

```bash
git clone https://github.com/makerjackie/codex-helper.git
cd codex-helper
./install.sh
```

Source builds use local ad-hoc signing and can require Accessibility permission again after rebuilding. For normal use, prefer the Developer ID-signed Release build.

## Test

```bash
./test.sh
```

## License

[MIT](LICENSE)
