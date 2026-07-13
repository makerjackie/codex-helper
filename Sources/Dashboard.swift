import AppKit

private final class DashboardStackView: NSStackView {
    override var isFlipped: Bool { true }
}

struct DashboardUsageRow {
    let name: String
    let percentText: String
    let usedPercent: Double
    let detail: String
}

struct DashboardLink {
    let title: String
    let subtitle: String?
    let url: URL
}

struct DashboardModel {
    let isChinese: Bool
    let version: String
    let statusTitle: String
    let statusDetail: String
    let accessibilityGranted: Bool
    let autoRetryEnabled: Bool
    let usageState: String
    let usageRows: [DashboardUsageRow]
    let usageFooter: String?
    let updatesState: String
    let updateActionTitle: String
    let updateActionEnabled: Bool
    let automaticUpdates: Bool
    let latestUpdates: [DashboardLink]
    let launchAtLogin: Bool
    let showQuotaInMenuBar: Bool
    let languageIndex: Int
}

struct DashboardActions {
    let target: AnyObject
    let openAccessibility: Selector
    let toggleAutoRetry: Selector
    let testAutoRetry: Selector
    let refreshUsage: Selector
    let performUpdate: Selector
    let toggleAutomaticUpdates: Selector
    let refreshNews: Selector
    let openLink: Selector
    let toggleLaunchAtLogin: Selector
    let toggleMenuBarQuota: Selector
    let changeLanguage: Selector
    let openLoginItems: Selector
    let openLogs: Selector
}

final class DashboardController {
    private let actions: DashboardActions
    private var window: NSWindow?
    private weak var rootStack: NSStackView?
    private var usageCard: NSView?
    private var updateCard: NSView?
    private var newsCard: NSView?

    init(actions: DashboardActions) {
        self.actions = actions
    }

    var isVisible: Bool { window?.isVisible == true }

    func show(model: DashboardModel) {
        if window == nil {
            window = makeWindow()
            window?.center()
        }
        update(model: model)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(model: DashboardModel) {
        guard let window else { return }
        let previousOrigin = (window.contentView as? NSScrollView)?.contentView.bounds.origin
        window.title = "Codex Helper"
        let content = makeContent(model: model)
        window.contentView = content
        if let previousOrigin, let scrollView = content as? NSScrollView {
            DispatchQueue.main.async {
                scrollView.contentView.scroll(to: previousOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    func updateUsage(model: DashboardModel) {
        let replacement = makeUsageCard(model: model)
        replaceCard(usageCard, with: replacement)
        usageCard = replacement
    }

    func updateAppUpdates(model: DashboardModel) {
        let replacement = makeUpdateCard(model: model)
        replaceCard(updateCard, with: replacement)
        updateCard = replacement
    }

    func updateNews(model: DashboardModel) {
        let replacement = makeNewsCard(model: model)
        replaceCard(newsCard, with: replacement)
        newsCard = replacement
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Helper"
        window.minSize = NSSize(width: 600, height: 560)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        return window
    }

    private func makeContent(model: DashboardModel) -> NSView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        let root = DashboardStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = root

        let title = NSTextField(labelWithString: "Codex Helper")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let version = NSTextField(labelWithString: model.isChinese ? "版本 \(model.version)" : "Version \(model.version)")
        version.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, version])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        root.addArrangedSubview(heading)

        let statusCard = makeStatusCard(model: model)
        let usageCard = makeUsageCard(model: model)
        let updateCard = makeUpdateCard(model: model)
        let newsCard = makeNewsCard(model: model)
        let generalCard = makeGeneralCard(model: model)
        self.usageCard = usageCard
        self.updateCard = updateCard
        self.newsCard = newsCard
        root.addArrangedSubview(statusCard)
        root.addArrangedSubview(usageCard)
        root.addArrangedSubview(updateCard)
        root.addArrangedSubview(newsCard)
        root.addArrangedSubview(generalCard)
        rootStack = root

        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        ])
        return scrollView
    }

    private func replaceCard(_ oldCard: NSView?, with newCard: NSView) {
        guard let rootStack, let oldCard,
              let index = rootStack.arrangedSubviews.firstIndex(where: { $0 === oldCard }) else { return }
        rootStack.removeArrangedSubview(oldCard)
        oldCard.removeFromSuperview()
        rootStack.insertArrangedSubview(newCard, at: index)
        newCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -56).isActive = true
    }

    private func makeStatusCard(model: DashboardModel) -> NSView {
        let title = label(model.statusTitle, font: .systemFont(ofSize: 16, weight: .semibold))
        let detail = wrappingLabel(model.statusDetail)
        detail.textColor = .secondaryLabelColor

        var views: [NSView] = [title, detail]
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 10

        let retry = NSButton(
            checkboxWithTitle: model.isChinese ? "启用自动重试" : "Enable Auto Retry",
            target: actions.target,
            action: actions.toggleAutoRetry
        )
        retry.state = model.autoRetryEnabled ? .on : .off
        controls.addArrangedSubview(retry)

        let test = button(model.isChinese ? "测试自动重试…" : "Test Auto Retry…", action: actions.testAutoRetry)
        test.isEnabled = model.accessibilityGranted && model.autoRetryEnabled
        controls.addArrangedSubview(test)

        if !model.accessibilityGranted {
            controls.addArrangedSubview(button(
                model.isChinese ? "立即授权…" : "Allow Accessibility…",
                action: actions.openAccessibility,
                emphasized: true
            ))
        }
        views.append(controls)
        return card(title: model.isChinese ? "自动重试" : "Auto Retry", views: views)
    }

    private func makeUsageCard(model: DashboardModel) -> NSView {
        var views: [NSView] = []
        let state = wrappingLabel(model.usageState)
        state.textColor = .secondaryLabelColor
        views.append(state)

        for usage in model.usageRows {
            let name = label(usage.name, font: .systemFont(ofSize: 14, weight: .semibold))
            let percent = label(usage.percentText, font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold))
            let heading = horizontalRow(left: name, right: percent)

            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.minValue = 0
            progress.maxValue = 100
            progress.doubleValue = min(max(usage.usedPercent, 0), 100)
            progress.isIndeterminate = false

            let detail = wrappingLabel(usage.detail)
            detail.textColor = .secondaryLabelColor
            detail.font = .systemFont(ofSize: 12)

            let row = NSStackView(views: [heading, progress, detail])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 7
            heading.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            progress.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            detail.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            views.append(row)
        }

        if let footer = model.usageFooter {
            let footerLabel = wrappingLabel(footer)
            footerLabel.textColor = .secondaryLabelColor
            footerLabel.font = .systemFont(ofSize: 12)
            views.append(footerLabel)
        }

        views.append(button(
            model.isChinese ? "刷新 Codex 额度" : "Refresh Codex Quota",
            action: actions.refreshUsage
        ))
        return card(title: model.isChinese ? "Codex 额度" : "Codex Quota", views: views)
    }

    private func makeUpdateCard(model: DashboardModel) -> NSView {
        let status = wrappingLabel(model.updatesState)
        status.textColor = .secondaryLabelColor
        let automatic = NSButton(
            checkboxWithTitle: model.isChinese ? "自动检查并下载更新" : "Automatically check and download updates",
            target: actions.target,
            action: actions.toggleAutomaticUpdates
        )
        automatic.state = model.automaticUpdates ? .on : .off
        let update = button(model.updateActionTitle, action: actions.performUpdate)
        update.isEnabled = model.updateActionEnabled
        return card(title: model.isChinese ? "应用更新" : "App Updates", views: [status, automatic, update])
    }

    private func makeNewsCard(model: DashboardModel) -> NSView {
        var views: [NSView] = []
        if model.latestUpdates.isEmpty {
            let empty = label(
                model.isChinese ? "暂无缓存动态。" : "No cached updates yet.",
                font: .systemFont(ofSize: 13)
            )
            empty.textColor = .secondaryLabelColor
            views.append(empty)
        } else {
            for update in model.latestUpdates {
                let link = linkButton(update.title, url: update.url)
                let source = label(update.subtitle ?? "", font: .systemFont(ofSize: 11))
                source.textColor = .tertiaryLabelColor
                let row = NSStackView(views: [link, source])
                row.orientation = .vertical
                row.alignment = .leading
                row.spacing = 2
                views.append(row)
            }
        }

        let refresh = button(model.isChinese ? "刷新动态" : "Refresh Updates", action: actions.refreshNews)
        let docs = linkButton(model.isChinese ? "Codex 官方文档" : "Codex Documentation", url: CodexResource.docs)
        let changelog = linkButton(model.isChinese ? "完整更新日志" : "Full Changelog", url: CodexResource.changelog)
        let resources = NSStackView(views: [refresh, docs, changelog])
        resources.orientation = .horizontal
        resources.spacing = 10
        views.append(resources)
        return card(title: model.isChinese ? "最新动态与文档" : "What’s New and Documentation", views: views)
    }

    private func makeGeneralCard(model: DashboardModel) -> NSView {
        let launch = NSButton(
            checkboxWithTitle: model.isChinese ? "登录时启动 Codex Helper" : "Launch Codex Helper at login",
            target: actions.target,
            action: actions.toggleLaunchAtLogin
        )
        launch.state = model.launchAtLogin ? .on : .off

        let quota = NSButton(
            checkboxWithTitle: model.isChinese ? "在菜单栏显示额度百分比" : "Show quota percentage in the menu bar",
            target: actions.target,
            action: actions.toggleMenuBarQuota
        )
        quota.state = model.showQuotaInMenuBar ? .on : .off

        let popup = NSPopUpButton()
        popup.addItems(withTitles: [model.isChinese ? "自动" : "Automatic", "English", "简体中文"])
        popup.selectItem(at: model.languageIndex)
        popup.target = actions.target
        popup.action = actions.changeLanguage
        let language = horizontalRow(
            left: label(model.isChinese ? "续跑消息语言" : "Continuation language", font: .systemFont(ofSize: 13)),
            right: popup
        )

        let loginItems = button(model.isChinese ? "登录项设置…" : "Login Items Settings…", action: actions.openLoginItems)
        let logs = button(model.isChinese ? "打开日志文件夹" : "Open Log Folder", action: actions.openLogs)
        let buttons = NSStackView(views: [loginItems, logs])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        return card(title: model.isChinese ? "常规设置" : "General", views: [launch, quota, language, buttons])
    }

    private func card(title: String, views: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 12

        let titleLabel = label(title, font: .systemFont(ofSize: 17, weight: .semibold))
        let stack = NSStackView(views: [titleLabel] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        for view in stack.arrangedSubviews where view !== titleLabel {
            if view is NSStackView || view is NSTextField {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            } else {
                view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
            }
        }
        return card
    }

    private func horizontalRow(left: NSView, right: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [left, spacer, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func button(_ title: String, action: Selector, emphasized: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: actions.target, action: action)
        button.bezelStyle = .rounded
        button.keyEquivalent = emphasized ? "\r" : ""
        return button
    }

    private func linkButton(_ title: String, url: URL) -> NSButton {
        let button = NSButton(title: title, target: actions.target, action: actions.openLink)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.alignment = .left
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.identifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        return button
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        return label
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.maximumNumberOfLines = 0
        return label
    }
}
