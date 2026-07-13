import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private lazy var agent = AutoRetryAgent(configStore: configStore)
    private lazy var updatesService = CodexUpdatesService(
        cacheURL: configStore.supportURL.appendingPathComponent("updates.json")
    )
    private let usageService = CodexUsageService()
    private lazy var updater = UpdateService(supportURL: configStore.supportURL)
    private var statusItem: NSStatusItem!
    private lazy var dashboardActions = DashboardActions(
        target: self,
        showDashboard: #selector(showDashboard(_:)),
        openAccessibility: #selector(openAccessibilitySettings(_:)),
        toggleAutoRetry: #selector(settingsAutoRetryChanged(_:)),
        testAutoRetry: #selector(testAutoRetry(_:)),
        refreshUsage: #selector(refreshUsage(_:)),
        toggleQuotaWidget: #selector(toggleQuotaWidget(_:)),
        performUpdate: #selector(performUpdateAction(_:)),
        toggleAutomaticUpdates: #selector(settingsAutomaticUpdatesChanged(_:)),
        refreshNews: #selector(refreshUpdates(_:)),
        openLink: #selector(openDashboardLink(_:)),
        toggleLaunchAtLogin: #selector(settingsLaunchChanged(_:)),
        toggleMenuBarQuota: #selector(settingsShowQuotaChanged(_:)),
        changeLanguage: #selector(settingsLanguageChanged(_:)),
        openLoginItems: #selector(openLoginItemsSettings(_:)),
        openLogs: #selector(openLogFolder(_:))
    )
    private lazy var dashboard = DashboardController(actions: dashboardActions)
    private lazy var quotaWidget = QuotaWidgetController(actions: dashboardActions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        syncLaunchAtLoginOnFirstRun()
        if configStore.load().autoRetryEnabled {
            agent.start()
        }
        usageService.onChange = { [weak self] in self?.refreshUsageInterface() }
        usageService.start()
        updater.onChange = { [weak self] in self?.refreshUpdaterInterface() }
        updater.start(automaticDownload: configStore.load().automaticUpdates)
        updatesService.refreshIfNeeded { [weak self] in
            self?.refreshNewsInterface()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agent.stop()
        usageService.stop()
        updater.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard statusItem != nil else { return }
        refreshInterface()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
        updatesService.refreshIfNeeded { [weak self] in
            self?.refreshNewsInterface()
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: "Codex Helper")
            button.imagePosition = .imageLeading
        }
        refreshInterface()
    }

    private func refreshInterface() {
        updateStatusItem()
        rebuildMenu()
        let model = makeDashboardModel()
        dashboard.update(model: model)
        syncQuotaWidget(model: model)
    }

    private func refreshUsageInterface() {
        updateStatusItem()
        rebuildMenu()
        let model = makeDashboardModel()
        dashboard.updateUsage(model: model)
        syncQuotaWidget(model: model)
    }

    private func refreshUpdaterInterface() {
        rebuildMenu()
        dashboard.updateAppUpdates(model: makeDashboardModel())
    }

    private func refreshNewsInterface() {
        rebuildMenu()
        dashboard.updateNews(model: makeDashboardModel())
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
        addUsageItems(to: menu)
        let widgetItem = NSMenuItem(
            title: text("Desktop Quota Widget", "桌面额度小组件"),
            action: #selector(toggleQuotaWidget(_:)),
            keyEquivalent: ""
        )
        widgetItem.target = self
        widgetItem.state = config.showQuotaWidget ? .on : .off
        menu.addItem(widgetItem)
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

        menu.addItem(makeUpdateMenuItem())

        let dashboard = NSMenuItem(title: text("Open Codex Helper…", "打开 Codex Helper…"), action: #selector(showDashboard(_:)), keyEquivalent: ",")
        dashboard.target = self
        menu.addItem(dashboard)

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
        refreshInterface()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        var config = configStore.load()
        config.language = language
        configStore.save(config)
        refreshInterface()
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
        refreshInterface()
    }

    @objc func showDashboard(_ sender: Any?) {
        dashboard.show(model: makeDashboardModel())
    }

    @objc private func toggleQuotaWidget(_ sender: Any?) {
        var config = configStore.load()
        config.showQuotaWidget.toggle()
        configStore.save(config)
        refreshInterface()
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

    @objc private func openDashboardLink(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshUpdates(_ sender: Any?) {
        updatesService.refreshIfNeeded(force: true) { [weak self] in
            self?.refreshNewsInterface()
        }
    }

    @objc private func refreshUsage(_ sender: Any?) {
        usageService.refresh()
    }

    @objc private func performUpdateAction(_ sender: Any?) {
        switch updater.state {
        case .ready:
            if updater.installReadyUpdate() {
                agent.stop()
                usageService.stop()
                updater.stop()
                NSApp.terminate(nil)
            } else {
                showError(text("The update could not be installed automatically.", "无法自动安装更新。"))
            }
        case .available:
            updater.downloadAvailableUpdate()
        default:
            updater.check(automaticDownload: false)
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

    @objc private func settingsAutomaticUpdatesChanged(_ sender: NSButton) {
        var config = configStore.load()
        config.automaticUpdates = sender.state == .on
        configStore.save(config)
        updater.setAutomaticDownload(config.automaticUpdates)
        if config.automaticUpdates { updater.check(automaticDownload: true) }
        refreshInterface()
    }

    @objc private func settingsShowQuotaChanged(_ sender: NSButton) {
        var config = configStore.load()
        config.showQuotaInMenuBar = sender.state == .on
        configStore.save(config)
        refreshInterface()
    }

    @objc private func settingsLanguageChanged(_ sender: NSPopUpButton) {
        let values = ["auto", "en", "zh"]
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        var config = configStore.load()
        config.language = values[sender.indexOfSelectedItem]
        configStore.save(config)
        refreshInterface()
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

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let config = configStore.load()
        let remainingPercent = primaryRemainingPercent
        let staleMarker: String
        if case .unavailable = usageService.status, usageService.snapshot != nil {
            staleMarker = " ⚠︎"
        } else {
            staleMarker = ""
        }
        button.title = config.showQuotaInMenuBar ? remainingPercent.map { "  \(formatQuotaPercent($0))\(staleMarker)" } ?? "" : ""
        if let remainingPercent {
            if staleMarker.isEmpty {
                button.toolTip = text(
                    "Codex quota: \(formatQuotaPercent(remainingPercent)) left",
                    "Codex 额度：剩余 \(formatQuotaPercent(remainingPercent))"
                )
            } else {
                button.toolTip = text(
                    "Codex quota: \(formatQuotaPercent(remainingPercent)) left · refresh failed",
                    "Codex 额度：剩余 \(formatQuotaPercent(remainingPercent)) · 刷新失败"
                )
            }
        } else {
            button.toolTip = text("Codex Helper · quota unavailable", "Codex Helper · 额度暂不可用")
        }
    }

    private func addUsageItems(to menu: NSMenu) {
        let headingTitle: String
        switch usageService.status {
        case .loading:
            headingTitle = text("Codex Quota · Refreshing…", "Codex 额度 · 正在刷新…")
        case .unavailable:
            headingTitle = usageService.snapshot == nil
                ? text("Codex Quota · Unavailable", "Codex 额度 · 暂不可用")
                : text("Codex Quota · Refresh failed", "Codex 额度 · 刷新失败")
        default:
            headingTitle = text("Codex Quota", "Codex 额度")
        }
        menu.addItem(disabledMenuItem(headingTitle))

        if let snapshot = usageService.snapshot {
            for limit in snapshot.limits {
                for window in [limit.primary, limit.secondary].compactMap({ $0 }) {
                    let duration = window.windowDurationMins.map(usageWindowLabel) ?? text("current window", "当前周期")
                    let reset = window.resetsAt.map(formatResetDate)
                    let suffix = reset.map { text(" · resets \($0)", " · 重置于 \($0)") } ?? ""
                    menu.addItem(disabledMenuItem(
                        "\(limit.name) · \(duration) · "
                            + text("\(formatQuotaPercent(window.remainingPercent)) left", "剩余 \(formatQuotaPercent(window.remainingPercent))")
                            + suffix
                    ))
                }
            }
            menu.addItem(disabledMenuItem(text(
                "Reset credits: \(snapshot.resetCredits)",
                "可用重置次数：\(snapshot.resetCredits)"
            )))
            menu.addItem(disabledMenuItem(text(
                "Updated \(formatResetDate(snapshot.fetchedAt))",
                "更新于 \(formatResetDate(snapshot.fetchedAt))"
            )))
        } else if case let .unavailable(message) = usageService.status {
            menu.addItem(disabledMenuItem(localizedUsageError(message)))
        } else {
            menu.addItem(disabledMenuItem(text("Reading account limits…", "正在读取账户额度…")))
        }

        let refresh = NSMenuItem(title: text("Refresh Codex Quota", "刷新 Codex 额度"), action: #selector(refreshUsage(_:)), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
    }

    private func disabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private var primaryRemainingPercent: Double? {
        let window = usageService.snapshot?.limits.first(where: { $0.id == "codex" })?.primary
            ?? usageService.snapshot?.limits.first?.primary
        return window?.remainingPercent
    }

    private func syncQuotaWidget(model: DashboardModel) {
        if model.showQuotaWidget {
            quotaWidget.show(model: model)
        } else {
            quotaWidget.hide()
        }
    }

    private func makeDashboardModel() -> DashboardModel {
        let config = configStore.load()
        let chinese = configStore.isChinese()
        let statusTitle: String
        let statusDetail: String
        if !config.autoRetryEnabled {
            statusTitle = text("Auto Retry is off", "自动重试已关闭")
            statusDetail = text(
                "Capacity errors will remain in Codex until you continue them manually.",
                "发生模型满载错误后，需要你在 Codex 中手动继续。"
            )
        } else if !agent.accessibilityGranted {
            statusTitle = text("Accessibility permission required", "需要辅助功能权限")
            statusDetail = text(
                "Quota and updates still work, but Auto Retry cannot submit continuation messages until permission is allowed.",
                "额度和更新仍可使用，但授权前自动重试无法在 Codex 中提交续跑消息。"
            )
        } else {
            statusTitle = text("Watching Codex", "正在监听 Codex")
            statusDetail = text(
                "Auto Retry is ready for selected-model capacity interruptions.",
                "自动重试已准备好处理所选模型满载中断。"
            )
        }

        let usageRows = makeDashboardUsageRows()
        let usageState: String
        if let snapshot = usageService.snapshot {
            switch usageService.status {
            case .loading:
                usageState = text("Refreshing the latest account limits…", "正在刷新最新账户额度…")
            case let .unavailable(message):
                usageState = text(
                    "Refresh failed; showing data from \(formatResetDate(snapshot.fetchedAt)). \(message)",
                    "刷新失败，正在显示 \(formatResetDate(snapshot.fetchedAt)) 的数据。"
                )
            default:
                usageState = text("Official Codex account limits", "Codex 官方账户额度")
            }
        } else {
            switch usageService.status {
            case let .unavailable(message): usageState = localizedUsageError(message)
            default: usageState = text("Reading the latest account limits…", "正在读取最新账户额度…")
            }
        }

        let usageFooter = usageService.snapshot.map {
            text(
                "Reset credits: \($0.resetCredits) · Updated \(formatResetDate($0.fetchedAt))",
                "可用重置次数：\($0.resetCredits) · 更新于 \(formatResetDate($0.fetchedAt))"
            )
        }
        let update = updatePresentation()
        let languageValues = ["auto", "en", "zh"]
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let links = updatesService.updates.prefix(3).map {
            DashboardLink(title: $0.title, subtitle: $0.source.displayName, url: $0.link)
        }

        return DashboardModel(
            isChinese: chinese,
            version: version,
            statusTitle: statusTitle,
            statusDetail: statusDetail,
            accessibilityGranted: agent.accessibilityGranted,
            autoRetryEnabled: config.autoRetryEnabled,
            usageState: usageState,
            usageRows: usageRows,
            usageFooter: usageFooter,
            updatesState: update.status,
            updateActionTitle: update.title,
            updateActionEnabled: update.enabled,
            automaticUpdates: config.automaticUpdates,
            latestUpdates: links,
            launchAtLogin: loginItemEnabled,
            showQuotaInMenuBar: config.showQuotaInMenuBar,
            showQuotaWidget: config.showQuotaWidget,
            languageIndex: languageValues.firstIndex(of: config.language) ?? 0
        )
    }

    private func makeDashboardUsageRows() -> [DashboardUsageRow] {
        guard let snapshot = usageService.snapshot else { return [] }
        return snapshot.limits.flatMap { limit in
            [limit.primary, limit.secondary].compactMap { window -> DashboardUsageRow? in
                guard let window else { return nil }
                let duration = window.windowDurationMins.map(usageWindowLabel) ?? text("Current window", "当前周期")
                let detail = window.resetsAt.map {
                    text("\(duration) window · Resets in \(formatResetDistance($0))", "\(duration) 周期 · \(formatResetDistance($0))后重置")
                } ?? text("\(duration) window", "\(duration) 周期")
                return DashboardUsageRow(
                    name: limit.name,
                    planText: limit.planType?.capitalized,
                    percentText: text("\(formatQuotaPercent(window.remainingPercent)) left", "剩余 \(formatQuotaPercent(window.remainingPercent))"),
                    remainingPercent: window.remainingPercent,
                    detail: detail
                )
            }
        }
    }

    private func updatePresentation() -> (title: String, enabled: Bool, status: String) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        switch updater.state {
        case .checking:
            return (text("Checking…", "正在检查…"), false, text("Checking GitHub Releases for updates.", "正在检查 GitHub Release。"))
        case let .available(release):
            return (
                text("Download \(release.version)…", "下载 \(release.version)…"),
                true,
                text("Version \(release.version) is available. Current version: \(current).", "发现 \(release.version) 版本，当前版本：\(current)。")
            )
        case let .downloading(release):
            return (text("Downloading \(release.version)…", "正在下载 \(release.version)…"), false, text("Downloading and verifying the signed update.", "正在下载并验证签名更新。"))
        case let .ready(update):
            return (
                text("Install \(update.release.version) and Restart…", "安装 \(update.release.version) 并重启…"),
                true,
                text("The signed update is ready to install.", "签名更新已准备好安装。")
            )
        case .upToDate:
            return (text("Check Again", "再次检查"), true, text("Codex Helper \(current) is up to date.", "Codex Helper \(current) 已是最新版本。"))
        case let .failed(message):
            return (
                text("Retry Update Check", "重新检查更新"),
                true,
                text("Update check failed: \(message)", "更新检查失败，请稍后重试。")
            )
        case .idle:
            return (text("Check for Updates…", "检查更新…"), true, text("Current version: \(current)", "当前版本：\(current)"))
        }
    }

    private func localizedUsageError(_ message: String) -> String {
        guard configStore.isChinese() else { return message }
        switch message {
        case "Codex CLI not found": return "未找到经过验证的 Codex App Server。"
        case "Codex usage service stopped": return "Codex 额度服务已停止，请尝试刷新。"
        case "Usage unavailable": return "Codex 额度暂不可用。"
        default: return "Codex 额度暂不可用，请稍后重试。"
        }
    }

    private func makeUpdateMenuItem() -> NSMenuItem {
        let presentation = updatePresentation()
        let item = NSMenuItem(title: presentation.title, action: #selector(performUpdateAction(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = presentation.enabled
        return item
    }

    private func usageWindowLabel(_ minutes: Int) -> String {
        if minutes % (24 * 60) == 0 { return "\(minutes / (24 * 60))d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private func formatResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = configStore.isChinese() ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatResetDistance(_ date: Date) -> String {
        let totalMinutes = max(Int(ceil(date.timeIntervalSinceNow / 60)), 0)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if configStore.isChinese() {
            if days > 0 { return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天" }
            if hours > 0 { return minutes > 0 ? "\(hours)小时\(minutes)分钟" : "\(hours)小时" }
            return "\(minutes)分钟"
        }
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
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
