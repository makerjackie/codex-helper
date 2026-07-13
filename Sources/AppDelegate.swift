import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private lazy var agent = AutoRetryAgent(configStore: configStore)
    private lazy var updatesService = CodexUpdatesService(
        cacheURL: configStore.supportURL.appendingPathComponent("updates.json")
    )
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private weak var autoRetryCheckbox: NSButton?
    private weak var launchCheckbox: NSButton?
    private weak var languagePopup: NSPopUpButton?
    private weak var accessibilityLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        syncLaunchAtLoginOnFirstRun()
        if configStore.load().autoRetryEnabled {
            agent.start()
        }
        updatesService.refreshIfNeeded { [weak self] in
            self?.rebuildMenu()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
        updatesService.refreshIfNeeded { [weak self] in
            self?.rebuildMenu()
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: "Codex Helper")
            button.toolTip = "Codex Helper"
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        populateMenu(menu)
        statusItem.menu = menu
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = configStore.load()

        let header = NSMenuItem(title: "Codex Helper", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let statusTitle: String
        if !config.autoRetryEnabled {
            statusTitle = text("Status: Auto Retry is off", "状态：自动重试已关闭")
        } else if !agent.accessibilityGranted {
            statusTitle = text("Status: Accessibility required", "状态：需要辅助功能权限")
        } else {
            statusTitle = text("Status: Watching Codex", "状态：正在监听 Codex")
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let retryItem = NSMenuItem(title: text("Auto Retry", "自动重试"), action: #selector(toggleAutoRetry(_:)), keyEquivalent: "")
        retryItem.target = self
        retryItem.state = config.autoRetryEnabled ? .on : .off
        menu.addItem(retryItem)

        let testItem = NSMenuItem(title: text("Test Auto Retry…", "测试自动重试…"), action: #selector(testAutoRetry(_:)), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let launchItem = NSMenuItem(title: text("Launch at Login", "登录时启动"), action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = loginItemEnabled ? .on : .off
        menu.addItem(launchItem)

        let languageItem = NSMenuItem(title: text("Language", "语言"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for (title, value) in [(text("Automatic", "自动"), "auto"), ("English", "en"), ("简体中文", "zh")] {
            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = config.language == value ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())

        menu.addItem(makeWhatsNewMenu())
        menu.addItem(makeLearnMenu())
        menu.addItem(.separator())

        let settings = NSMenuItem(title: text("Settings…", "设置…"), action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        if !agent.accessibilityGranted {
            let permission = NSMenuItem(title: text("Open Accessibility Settings…", "打开辅助功能设置…"), action: #selector(openAccessibilitySettings(_:)), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }

        let logs = NSMenuItem(title: text("Open Log Folder", "打开日志文件夹"), action: #selector(openLogFolder(_:)), keyEquivalent: "")
        logs.target = self
        menu.addItem(logs)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: text("Quit Codex Helper", "退出 Codex Helper"), action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleAutoRetry(_ sender: Any?) {
        var config = configStore.load()
        config.autoRetryEnabled.toggle()
        configStore.save(config)
        config.autoRetryEnabled ? agent.start() : agent.stop()
        rebuildMenu()
        refreshSettingsControls()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        var config = configStore.load()
        config.language = language
        configStore.save(config)
        let settingsWereVisible = settingsWindow?.isVisible == true
        if settingsWereVisible {
            settingsWindow?.close()
            settingsWindow = nil
        }
        rebuildMenu()
        if settingsWereVisible {
            showSettings(nil)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        let shouldEnable = !loginItemEnabled
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            var config = configStore.load()
            config.launchAtLogin = shouldEnable
            configStore.save(config)
        } catch {
            showError(error.localizedDescription)
        }
        rebuildMenu()
        refreshSettingsControls()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        refreshSettingsControls()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        agent.promptForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLoginItemsSettings(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLogFolder(_ sender: Any?) {
        NSWorkspace.shared.open(configStore.supportURL)
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshUpdates(_ sender: Any?) {
        updatesService.refreshIfNeeded(force: true) { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc private func testAutoRetry(_ sender: Any?) {
        guard agent.accessibilityGranted else {
            let alert = NSAlert()
            alert.messageText = text("Accessibility permission is required", "需要辅助功能权限")
            alert.informativeText = text(
                "Allow Codex Helper in System Settings before running the end-to-end test.",
                "请先在系统设置中允许 Codex Helper 使用辅助功能，再运行端到端测试。"
            )
            alert.addButton(withTitle: text("Open Settings", "打开设置"))
            alert.addButton(withTitle: text("Cancel", "取消"))
            if alert.runModal() == .alertFirstButtonReturn {
                openAccessibilitySettings(nil)
            }
            return
        }

        let threads = agent.recentVisibleThreads()
        guard !threads.isEmpty else {
            showError(text("No recent visible Codex tasks were found.", "没有找到最近的可见 Codex 任务。"))
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 430, height: 28))
        for thread in threads {
            popup.addItem(withTitle: "\(thread.name) — \(thread.id.prefix(8))")
        }

        let alert = NSAlert()
        alert.messageText = text("Test Auto Retry end to end", "端到端测试自动重试")
        alert.informativeText = text(
            "Choose a task. Codex Helper will open it and submit one clearly marked test message after 3 seconds. This verifies task routing, Accessibility control, text entry, and submission without waiting for a real capacity error.",
            "选择一个任务。3 秒后 Codex Helper 会打开它并提交一条明确标记的测试消息，无需等待真实满载错误，即可验证任务定位、辅助功能控制、文字输入和提交。"
        )
        alert.accessoryView = popup
        alert.addButton(withTitle: text("Run Test", "运行测试"))
        alert.addButton(withTitle: text("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let selectedIndex = popup.indexOfSelectedItem
        guard threads.indices.contains(selectedIndex), agent.runEndToEndTest(threadID: threads[selectedIndex].id, completion: { [weak self] success, reason in
            self?.showEndToEndTestResult(success: success, reason: reason)
        }) else {
            showError(text("The selected task could not be tested.", "无法测试所选任务。"))
            return
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        agent.stop()
        NSApp.terminate(nil)
    }

    @objc private func settingsAutoRetryChanged(_ sender: NSButton) {
        toggleAutoRetry(sender)
    }

    @objc private func settingsLaunchChanged(_ sender: NSButton) {
        toggleLaunchAtLogin(sender)
    }

    @objc private func settingsLanguageChanged(_ sender: NSPopUpButton) {
        let values = ["auto", "en", "zh"]
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        var config = configStore.load()
        config.language = values[sender.indexOfSelectedItem]
        configStore.save(config)
        settingsWindow?.close()
        settingsWindow = nil
        rebuildMenu()
        showSettings(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = text("Codex Helper Settings", "Codex Helper 设置")
        window.isReleasedWhenClosed = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        let title = NSTextField(labelWithString: "Codex Helper")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: text(
            "Small utilities that make Codex more reliable. Auto Retry is the first feature.",
            "让 Codex 更顺手的一组小工具，自动重试是第一个功能。"
        ))
        subtitle.textColor = .secondaryLabelColor

        let retry = NSButton(checkboxWithTitle: text("Enable Auto Retry", "启用自动重试"), target: self, action: #selector(settingsAutoRetryChanged(_:)))
        autoRetryCheckbox = retry

        let launch = NSButton(checkboxWithTitle: text("Launch Codex Helper at login", "登录时启动 Codex Helper"), target: self, action: #selector(settingsLaunchChanged(_:)))
        launchCheckbox = launch

        let popup = NSPopUpButton()
        popup.addItems(withTitles: [text("Automatic", "自动"), "English", "简体中文"])
        popup.target = self
        popup.action = #selector(settingsLanguageChanged(_:))
        languagePopup = popup
        let languageRow = row(label: text("Continuation language", "续跑消息语言"), control: popup)

        let permission = NSTextField(labelWithString: "")
        permission.textColor = .secondaryLabelColor
        accessibilityLabel = permission
        let permissionButton = NSButton(title: text("Accessibility Settings…", "辅助功能设置…"), target: self, action: #selector(openAccessibilitySettings(_:)))
        permissionButton.bezelStyle = .rounded
        let permissionRow = row(label: permission.stringValue, control: permissionButton)
        if let label = permissionRow.arrangedSubviews.first as? NSTextField {
            accessibilityLabel = label
        }

        let loginButton = NSButton(title: text("Login Items Settings…", "登录项设置…"), target: self, action: #selector(openLoginItemsSettings(_:)))
        loginButton.bezelStyle = .rounded
        let logButton = NSButton(title: text("Open Log Folder", "打开日志文件夹"), target: self, action: #selector(openLogFolder(_:)))
        logButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [loginButton, logButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, subtitle, retry, launch, languageRow, permissionRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            languageRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return window
    }

    private func row(label: String, control: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [labelView, spacer, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func refreshSettingsControls() {
        let config = configStore.load()
        autoRetryCheckbox?.state = config.autoRetryEnabled ? .on : .off
        launchCheckbox?.state = loginItemEnabled ? .on : .off
        let values = ["auto", "en", "zh"]
        languagePopup?.selectItem(at: values.firstIndex(of: config.language) ?? 0)
        accessibilityLabel?.stringValue = agent.accessibilityGranted
            ? text("Accessibility: Allowed", "辅助功能：已允许")
            : text("Accessibility: Permission required", "辅助功能：需要授权")
    }

    private var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func syncLaunchAtLoginOnFirstRun() {
        let config = configStore.load()
        guard config.launchAtLogin, SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
    }

    private func text(_ english: String, _ chinese: String) -> String {
        configStore.isChinese() ? chinese : english
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = text("Codex Helper could not complete that action.", "Codex Helper 无法完成该操作。")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showEndToEndTestResult(success: Bool, reason: String) {
        let alert = NSAlert()
        if success {
            alert.messageText = text("Auto Retry test passed", "自动重试测试通过")
            alert.informativeText = text(
                "The synthetic capacity error was routed to the selected task and the test prompt was confirmed in that task. Its Codex reply should appear shortly.",
                "模拟容量错误已定位到所选任务，测试消息也已在该任务中得到确认；Codex 的回复应该很快出现。"
            )
            alert.alertStyle = .informational
        } else {
            let explanations: [String: (String, String)] = [
                "newActivity": ("The task changed while the test was waiting.", "等待期间任务出现了新活动。"),
                "codexNotRunning": ("Codex was not running.", "Codex 未在运行。"),
                "codexNotFrontmost": ("Codex could not become the frontmost app.", "Codex 无法切换到前台。"),
                "focusChanged": ("Focus left Codex before submission.", "提交前焦点离开了 Codex。"),
                "targetNotSelected": ("The selected task could not be verified in the Codex sidebar.", "无法在 Codex 侧边栏确认所选任务。"),
                "composerNotEmpty": ("The focused Codex composer was not empty or could not be verified.", "Codex 当前输入框不是空白状态，或无法验证。"),
                "targetNotConfirmed": ("The test prompt was not confirmed in the selected task.", "无法确认测试消息已进入所选任务。")
            ]
            let explanation = explanations[reason] ?? ("The test was cancelled before submission.", "测试在提交前已取消。")
            alert.messageText = text("Auto Retry test did not complete", "自动重试测试未完成")
            let followUp = reason == "targetNotConfirmed"
                ? text(
                    "The prompt may have been submitted, but the target-session check failed. Inspect the selected task and log folder before trying again.",
                    "测试消息可能已经提交，但目标任务确认失败；再次尝试前请检查所选任务和日志文件夹。"
                )
                : text(
                    "No retry was sent because a pre-submission safety check failed. You can inspect the log folder for details.",
                    "提交前安全检查失败，因此没有发送重试消息；可以打开日志文件夹查看详情。"
                )
            alert.informativeText = text(explanation.0, explanation.1) + "\n\n" + followUp
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    private func makeWhatsNewMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: text("What’s New", "最新动态"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if updatesService.updates.isEmpty {
            let emptyTitle = updatesService.isRefreshing
                ? text("Loading official updates…", "正在载入官方动态…")
                : text("No cached updates", "暂无缓存动态")
            let empty = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for update in updatesService.updates.prefix(5) {
                let item = NSMenuItem(title: update.title, action: #selector(openURL(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = update.link
                item.toolTip = update.source.displayName
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        let refresh = NSMenuItem(title: text("Refresh", "刷新"), action: #selector(refreshUpdates(_:)), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !updatesService.isRefreshing
        submenu.addItem(refresh)
        submenu.addItem(resourceItem(text("Open full Codex changelog", "打开完整 Codex 更新日志"), url: CodexResource.changelog))
        parent.submenu = submenu
        return parent
    }

    private func makeLearnMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: text("Learn Codex", "了解 Codex"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(resourceItem(text("Codex Documentation", "Codex 官方文档"), url: CodexResource.docs))
        submenu.addItem(resourceItem(text("Commands", "命令参考"), url: CodexResource.commands))
        submenu.addItem(resourceItem(text("Troubleshooting", "故障排查"), url: CodexResource.troubleshooting))
        submenu.addItem(.separator())
        submenu.addItem(resourceItem(text("Tibo · Head of Codex on X", "Tibo · Codex 负责人动态"), url: CodexResource.tibo))
        parent.submenu = submenu
        return parent
    }

    private func resourceItem(_ title: String, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openURL(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        return item
    }
}
