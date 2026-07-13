import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private lazy var agent = AutoRetryAgent(configStore: configStore)
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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
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
}
