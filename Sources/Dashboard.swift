import AppKit

private final class DashboardStackView: NSStackView {
    override var isFlipped: Bool { true }
}

struct DashboardUsageRow {
    let name: String
    let planText: String?
    let percentText: String
    let remainingPercent: Double
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
    let showQuotaWidget: Bool
    let languageIndex: Int
}

struct DashboardActions {
    let target: AnyObject
    let showDashboard: Selector
    let openAccessibility: Selector
    let toggleAutoRetry: Selector
    let testAutoRetry: Selector
    let refreshUsage: Selector
    let toggleQuotaWidget: Selector
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

    func updateUsage(model: DashboardModel) { update(model: model) }
    func updateAppUpdates(model: DashboardModel) { update(model: model) }
    func updateNews(model: DashboardModel) { update(model: model) }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Helper"
        window.minSize = NSSize(width: 760, height: 600)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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
        root.spacing = 22
        root.edgeInsets = NSEdgeInsets(top: 34, left: 34, bottom: 34, right: 34)
        root.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = root

        let header = makeHeader(model: model)
        let hero = makeQuotaHero(model: model)
        let workspace = makeWorkspace(model: model)
        let news = makeNewsSection(model: model)
        [header, hero, workspace, news].forEach(root.addArrangedSubview)

        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -68).isActive = true
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        ])
        return scrollView
    }

    private func makeHeader(model: DashboardModel) -> NSView {
        let title = label("Codex Helper", font: .systemFont(ofSize: 30, weight: .bold))
        let subtitle = label(
            model.isChinese ? "Mac 上的 Codex 辅助工具 · v\(model.version)" : "A focused Codex companion for Mac · v\(model.version)",
            font: .systemFont(ofSize: 13)
        )
        subtitle.textColor = .secondaryLabelColor
        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 5

        let status = pillLabel(
            model.statusTitle,
            color: model.accessibilityGranted && model.autoRetryEnabled ? .systemGreen : .systemOrange
        )
        return makeHorizontalRow(left: copy, right: status)
    }

    private func makeQuotaHero(model: DashboardModel) -> NSView {
        let primary = model.usageRows.first
        let level = quotaLevel(for: primary?.remainingPercent)
        let surface = QuotaSurfaceView(level: level, cornerRadius: 24)
        surface.translatesAutoresizingMaskIntoConstraints = false

        let sectionTitle = label(model.isChinese ? "CODEX 额度" : "CODEX QUOTA", font: .systemFont(ofSize: 12, weight: .semibold))
        sectionTitle.textColor = .secondaryLabelColor
        let state = label(model.usageState, font: .systemFont(ofSize: 12))
        state.textColor = .secondaryLabelColor
        let top = makeHorizontalRow(left: sectionTitle, right: state)

        var arranged: [NSView] = [top]
        if let primary {
            let identity = primary.planText.map { "\(primary.name) · \($0)" } ?? primary.name
            let name = label(identity.uppercased(), font: .systemFont(ofSize: 14, weight: .semibold))
            name.textColor = .secondaryLabelColor

            let value = label(formatQuotaPercent(primary.remainingPercent), font: .monospacedDigitSystemFont(ofSize: 52, weight: .medium))
            let remaining = label(model.isChinese ? "剩余" : "left", font: .systemFont(ofSize: 15, weight: .medium))
            remaining.textColor = .secondaryLabelColor
            let valueRow = NSStackView(views: [value, remaining])
            valueRow.orientation = .horizontal
            valueRow.alignment = .lastBaseline
            valueRow.spacing = 8

            let detail = label(primary.detail, font: .systemFont(ofSize: 12))
            detail.textColor = .secondaryLabelColor
            let progress = QuotaProgressView(remainingPercent: primary.remainingPercent, level: level)
            arranged += [name, valueRow, progress, detail]

            for usage in model.usageRows.dropFirst() {
                arranged.append(divider())
                let secondaryName = label(usage.name, font: .systemFont(ofSize: 13, weight: .semibold))
                let secondaryValue = label(usage.percentText, font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
                let row = makeHorizontalRow(left: secondaryName, right: secondaryValue)
                let secondaryProgress = QuotaProgressView(
                    remainingPercent: usage.remainingPercent,
                    level: quotaLevel(for: usage.remainingPercent)
                )
                let secondaryDetail = label(usage.detail, font: .systemFont(ofSize: 11))
                secondaryDetail.textColor = .secondaryLabelColor
                arranged += [row, secondaryProgress, secondaryDetail]
            }
        } else {
            let empty = wrappingLabel(model.usageState)
            empty.font = .systemFont(ofSize: 18, weight: .medium)
            arranged.append(empty)
        }

        if let footer = model.usageFooter {
            let footerLabel = label(footer, font: .systemFont(ofSize: 11))
            footerLabel.textColor = .secondaryLabelColor
            arranged.append(footerLabel)
        }

        let refresh = button(model.isChinese ? "刷新额度" : "Refresh", action: actions.refreshUsage)
        let widgetTitle: String
        if model.showQuotaWidget {
            widgetTitle = model.isChinese ? "隐藏桌面小组件" : "Hide Desktop Widget"
        } else {
            widgetTitle = model.isChinese ? "显示桌面小组件" : "Show Desktop Widget"
        }
        let widget = button(widgetTitle, action: actions.toggleQuotaWidget, emphasized: true)
        let controls = NSStackView(views: [widget, refresh])
        controls.orientation = .horizontal
        controls.spacing = 8
        arranged.append(controls)

        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -22)
        ])
        pinFullWidthViews(in: stack)
        return surface
    }

    private func makeWorkspace(model: DashboardModel) -> NSView {
        let retry = makeRetrySection(model: model)
        let controls = makeControlCenter(model: model)
        let grid = NSStackView(views: [retry, controls])
        grid.orientation = .horizontal
        grid.alignment = .top
        grid.distribution = .fillEqually
        grid.spacing = 18
        return grid
    }

    private func makeRetrySection(model: DashboardModel) -> NSView {
        let icon = symbolView("arrow.triangle.2.circlepath", color: .systemPurple)
        let heading = label(model.isChinese ? "自动重试" : "Auto Retry", font: .systemFont(ofSize: 18, weight: .semibold))
        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let status = label(model.statusTitle, font: .systemFont(ofSize: 14, weight: .medium))
        let detail = wrappingLabel(model.statusDetail)
        detail.textColor = .secondaryLabelColor

        let retry = NSButton(
            checkboxWithTitle: model.isChinese ? "启用自动重试" : "Enable Auto Retry",
            target: actions.target,
            action: actions.toggleAutoRetry
        )
        retry.state = model.autoRetryEnabled ? .on : .off
        let test = button(model.isChinese ? "测试自动重试…" : "Test Auto Retry…", action: actions.testAutoRetry)
        test.isEnabled = model.accessibilityGranted && model.autoRetryEnabled

        var views: [NSView] = [header, status, detail, retry, test]
        if !model.accessibilityGranted {
            views.append(button(
                model.isChinese ? "授予辅助功能权限…" : "Allow Accessibility…",
                action: actions.openAccessibility,
                emphasized: true
            ))
        }
        return groupSurface(views: views)
    }

    private func makeControlCenter(model: DashboardModel) -> NSView {
        let heading = label(model.isChinese ? "控制中心" : "Control Center", font: .systemFont(ofSize: 18, weight: .semibold))
        let updateTitle = label(model.isChinese ? "应用更新" : "App Updates", font: .systemFont(ofSize: 14, weight: .medium))
        let updateStatus = wrappingLabel(model.updatesState)
        updateStatus.textColor = .secondaryLabelColor
        updateStatus.font = .systemFont(ofSize: 12)
        let updateButton = button(model.updateActionTitle, action: actions.performUpdate)
        updateButton.isEnabled = model.updateActionEnabled

        let automatic = NSButton(
            checkboxWithTitle: model.isChinese ? "自动检查并下载更新" : "Automatically check and download updates",
            target: actions.target,
            action: actions.toggleAutomaticUpdates
        )
        automatic.state = model.automaticUpdates ? .on : .off

        let launch = NSButton(
            checkboxWithTitle: model.isChinese ? "登录时启动" : "Launch at login",
            target: actions.target,
            action: actions.toggleLaunchAtLogin
        )
        launch.state = model.launchAtLogin ? .on : .off

        let quota = NSButton(
            checkboxWithTitle: model.isChinese ? "菜单栏显示剩余额度" : "Show remaining quota in menu bar",
            target: actions.target,
            action: actions.toggleMenuBarQuota
        )
        quota.state = model.showQuotaInMenuBar ? .on : .off

        let popup = NSPopUpButton()
        popup.addItems(withTitles: [model.isChinese ? "自动" : "Automatic", "English", "简体中文"])
        popup.selectItem(at: model.languageIndex)
        popup.target = actions.target
        popup.action = actions.changeLanguage
        let language = makeHorizontalRow(
            left: label(model.isChinese ? "界面与续跑语言" : "Interface and retry language", font: .systemFont(ofSize: 13)),
            right: popup
        )

        let loginItems = button(model.isChinese ? "登录项设置…" : "Login Items…", action: actions.openLoginItems)
        let logs = button(model.isChinese ? "日志" : "Logs", action: actions.openLogs)
        let utilityButtons = NSStackView(views: [loginItems, logs])
        utilityButtons.orientation = .horizontal
        utilityButtons.spacing = 8

        return groupSurface(views: [
            heading, updateTitle, updateStatus, updateButton, automatic,
            divider(), launch, quota, language, utilityButtons
        ])
    }

    private func makeNewsSection(model: DashboardModel) -> NSView {
        let title = label(model.isChinese ? "最新动态与文档" : "What’s New and Documentation", font: .systemFont(ofSize: 18, weight: .semibold))
        let refresh = button(model.isChinese ? "刷新" : "Refresh", action: actions.refreshNews)
        var views: [NSView] = [makeHorizontalRow(left: title, right: refresh)]

        if model.latestUpdates.isEmpty {
            let empty = label(model.isChinese ? "暂无缓存动态。" : "No cached updates yet.", font: .systemFont(ofSize: 13))
            empty.textColor = .secondaryLabelColor
            views.append(empty)
        } else {
            for (index, update) in model.latestUpdates.enumerated() {
                if index > 0 { views.append(divider()) }
                let link = linkButton(update.title, url: update.url)
                let source = label(update.subtitle ?? "", font: .systemFont(ofSize: 11))
                source.textColor = .tertiaryLabelColor
                let row = NSStackView(views: [link, source])
                row.orientation = .vertical
                row.alignment = .leading
                row.spacing = 3
                views.append(row)
            }
        }

        let docs = linkButton(model.isChinese ? "Codex 官方文档" : "Codex Documentation", url: CodexResource.docs)
        let changelog = linkButton(model.isChinese ? "完整更新日志" : "Full Changelog", url: CodexResource.changelog)
        let resources = NSStackView(views: [docs, changelog])
        resources.orientation = .horizontal
        resources.spacing = 14
        views.append(resources)
        return groupSurface(views: views)
    }

    private func groupSurface(views: [NSView]) -> NSView {
        let surface = DashboardSurfaceView(cornerRadius: 16)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 17),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -17)
        ])
        pinFullWidthViews(in: stack)
        return surface
    }

    private func pinFullWidthViews(in stack: NSStackView) {
        for view in stack.arrangedSubviews {
            if view is NSStackView || view is NSTextField || view is QuotaProgressView {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            } else {
                view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
            }
        }
    }

    private func divider() -> NSView {
        let divider = DashboardDividerView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
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

    private func symbolView(_ name: String, color: NSColor) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = color
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 20),
            view.heightAnchor.constraint(equalToConstant: 20)
        ])
        return view
    }

    private func pillLabel(_ text: String, color: NSColor) -> NSTextField {
        StatusPillLabel(text: "  ●  \(text)  ", color: color)
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
