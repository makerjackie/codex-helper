import AppKit

private final class DashboardStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class DashboardCanvasView: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

struct DashboardUsageRow {
    let name: String
    let planText: String?
    let percentText: String
    let remainingPercent: Double
    let detail: String

    var displayIdentity: String {
        planText.map { "\(name) · \($0)" } ?? name
    }
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
        window.contentView = makeContent(model: model)
        if let previousOrigin, let scrollView = window.contentView as? NSScrollView {
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Helper"
        window.minSize = NSSize(width: 720, height: 580)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = .windowBackgroundColor
        return window
    }

    private func makeContent(model: DashboardModel) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false

        let canvas = DashboardCanvasView()
        canvas.material = .contentBackground
        canvas.blendingMode = .withinWindow
        canvas.state = .active
        canvas.translatesAutoresizingMaskIntoConstraints = false

        let root = DashboardStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 24
        root.edgeInsets = NSEdgeInsets(top: 38, left: 38, bottom: 38, right: 38)
        root.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(root)
        scroll.documentView = canvas

        let sections = [
            makeHeader(model: model),
            makeQuotaOverview(model: model),
            divider(),
            makeOperations(model: model),
            divider(),
            makeUpdateStrip(model: model),
            divider(),
            makeNewsSection(model: model)
        ]
        sections.forEach(root.addArrangedSubview)
        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -76).isActive = true
        }
        NSLayoutConstraint.activate([
            canvas.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            canvas.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            root.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            root.topAnchor.constraint(equalTo: canvas.topAnchor),
            root.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)
        ])
        return scroll
    }

    private func makeHeader(model: DashboardModel) -> NSView {
        let title = label("Codex Helper", font: .systemFont(ofSize: 29, weight: .bold))
        let subtitle = label(
            model.isChinese ? "安静地守着 Codex 的状态 · v\(model.version)" : "A quiet status rail for Codex · v\(model.version)",
            font: .systemFont(ofSize: 13)
        )
        subtitle.textColor = .secondaryLabelColor
        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 5

        let statusColor: NSColor = model.accessibilityGranted && model.autoRetryEnabled ? .systemGreen : .systemOrange
        let status = StatusPillLabel(text: "  ●  \(model.statusTitle)  ", color: statusColor)
        return makeHorizontalRow(left: copy, right: status)
    }

    private func makeQuotaOverview(model: DashboardModel) -> NSView {
        let primary = model.usageRows.first
        let surface = NeutralSurfaceView(cornerRadius: 22)
        surface.translatesAutoresizingMaskIntoConstraints = false

        let ring = QuotaRingView(remainingPercent: primary?.remainingPercent, lineWidth: 11)
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 132),
            ring.heightAnchor.constraint(equalToConstant: 132)
        ])

        let identity = primary?.displayIdentity ?? "Codex"
        let eyebrow = label(model.isChinese ? "剩余额度" : "REMAINING QUOTA", font: .systemFont(ofSize: 11, weight: .semibold))
        eyebrow.textColor = .secondaryLabelColor
        let name = label(identity, font: .systemFont(ofSize: 20, weight: .semibold))
        let reset = wrappingLabel(primary?.detail ?? model.usageState)
        reset.font = .systemFont(ofSize: 12)
        reset.textColor = .secondaryLabelColor

        var overviewViews: [NSView] = [eyebrow, name, reset]
        for secondary in model.usageRows.dropFirst() {
            let dot = QuotaAccentDotView(level: quotaLevel(for: secondary.remainingPercent))
            let secondaryName = label(secondary.displayIdentity, font: .systemFont(ofSize: 12, weight: .medium))
            let secondaryValue = label(secondary.percentText, font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold))
            let secondaryUsageLabel = NSStackView(views: [dot, secondaryName])
            secondaryUsageLabel.orientation = .horizontal
            secondaryUsageLabel.alignment = .centerY
            secondaryUsageLabel.spacing = 7
            overviewViews.append(makeHorizontalRow(left: secondaryUsageLabel, right: secondaryValue))
            let secondaryDetail = label(secondary.detail, font: .systemFont(ofSize: 10))
            secondaryDetail.textColor = .tertiaryLabelColor
            overviewViews.append(secondaryDetail)
        }
        let overview = NSStackView(views: overviewViews)
        overview.orientation = .vertical
        overview.alignment = .leading
        overview.spacing = 9

        let refresh = button(model.isChinese ? "刷新" : "Refresh", action: actions.refreshUsage)
        let widgetTitle = model.showQuotaWidget
            ? (model.isChinese ? "隐藏状态轨道" : "Hide Status Rail")
            : (model.isChinese ? "显示状态轨道" : "Show Status Rail")
        let widget = button(widgetTitle, action: actions.toggleQuotaWidget, emphasized: true)
        let controls = NSStackView(views: [widget, refresh])
        controls.orientation = .vertical
        controls.alignment = .trailing
        controls.spacing = 8
        let footer = label(model.usageFooter ?? "", font: .systemFont(ofSize: 10))
        footer.textColor = .tertiaryLabelColor
        controls.addArrangedSubview(footer)

        let layout = NSStackView(views: [ring, overview, controls])
        layout.orientation = .horizontal
        layout.alignment = .centerY
        layout.spacing = 22
        layout.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            layout.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -22),
            layout.topAnchor.constraint(equalTo: surface.topAnchor, constant: 22),
            layout.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -22),
            overview.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
        for view in overview.arrangedSubviews where view is NSStackView || view is NSTextField {
            view.widthAnchor.constraint(equalTo: overview.widthAnchor).isActive = true
        }
        return surface
    }

    private func makeOperations(model: DashboardModel) -> NSView {
        let retry = makeRetrySection(model: model)
        let separator = DashboardDividerView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let preferences = makePreferences(model: model)

        let layout = NSStackView(views: [retry, separator, preferences])
        layout.orientation = .horizontal
        layout.alignment = .top
        layout.spacing = 26
        retry.widthAnchor.constraint(equalTo: preferences.widthAnchor).isActive = true
        separator.heightAnchor.constraint(equalTo: layout.heightAnchor).isActive = true
        return layout
    }

    private func makeRetrySection(model: DashboardModel) -> NSView {
        let heading = sectionHeading(symbol: "arrow.triangle.2.circlepath", title: model.isChinese ? "自动重试" : "Auto Retry", color: .systemPurple)
        let status = label(model.statusTitle, font: .systemFont(ofSize: 14, weight: .medium))
        let detail = wrappingLabel(model.statusDetail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor

        let enabled = NSButton(
            checkboxWithTitle: model.isChinese ? "启用自动重试" : "Enable Auto Retry",
            target: actions.target,
            action: actions.toggleAutoRetry
        )
        enabled.state = model.autoRetryEnabled ? .on : .off
        let test = button(model.isChinese ? "运行端到端测试…" : "Run End-to-End Test…", action: actions.testAutoRetry)
        test.isEnabled = model.accessibilityGranted && model.autoRetryEnabled

        var views: [NSView] = [heading, status, detail, enabled, test]
        if !model.accessibilityGranted {
            views.append(button(
                model.isChinese ? "授予辅助功能权限…" : "Allow Accessibility…",
                action: actions.openAccessibility,
                emphasized: true
            ))
        }
        return verticalSection(views)
    }

    private func makePreferences(model: DashboardModel) -> NSView {
        let heading = sectionHeading(symbol: "slider.horizontal.3", title: model.isChinese ? "偏好设置" : "Preferences", color: .systemTeal)
        let launch = NSButton(
            checkboxWithTitle: model.isChinese ? "登录时启动" : "Launch at login",
            target: actions.target,
            action: actions.toggleLaunchAtLogin
        )
        launch.state = model.launchAtLogin ? .on : .off
        let menuQuota = NSButton(
            checkboxWithTitle: model.isChinese ? "菜单栏显示剩余额度" : "Show quota in menu bar",
            target: actions.target,
            action: actions.toggleMenuBarQuota
        )
        menuQuota.state = model.showQuotaInMenuBar ? .on : .off

        let popup = NSPopUpButton()
        popup.addItems(withTitles: [model.isChinese ? "自动" : "Automatic", "English", "简体中文"])
        popup.selectItem(at: model.languageIndex)
        popup.target = actions.target
        popup.action = actions.changeLanguage
        let language = makeHorizontalRow(
            left: label(model.isChinese ? "界面与续跑语言" : "Interface and retry language", font: .systemFont(ofSize: 12)),
            right: popup
        )

        let loginItems = button(model.isChinese ? "登录项…" : "Login Items…", action: actions.openLoginItems)
        let logs = button(model.isChinese ? "日志" : "Logs", action: actions.openLogs)
        let utility = NSStackView(views: [loginItems, logs])
        utility.orientation = .horizontal
        utility.spacing = 8
        return verticalSection([heading, launch, menuQuota, language, utility])
    }

    private func makeUpdateStrip(model: DashboardModel) -> NSView {
        let heading = sectionHeading(symbol: "arrow.down.circle", title: model.isChinese ? "应用更新" : "App Updates", color: .systemBlue)
        let state = wrappingLabel(model.updatesState)
        state.font = .systemFont(ofSize: 12)
        state.textColor = .secondaryLabelColor
        let copy = NSStackView(views: [heading, state])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 6

        let automatic = NSButton(
            checkboxWithTitle: model.isChinese ? "自动下载" : "Auto-download",
            target: actions.target,
            action: actions.toggleAutomaticUpdates
        )
        automatic.state = model.automaticUpdates ? .on : .off
        let action = button(model.updateActionTitle, action: actions.performUpdate)
        action.isEnabled = model.updateActionEnabled
        let controls = NSStackView(views: [automatic, action])
        controls.orientation = .horizontal
        controls.spacing = 10
        return makeHorizontalRow(left: copy, right: controls)
    }

    private func makeNewsSection(model: DashboardModel) -> NSView {
        let heading = sectionHeading(symbol: "newspaper", title: model.isChinese ? "Codex 动态" : "Codex Updates", color: .systemIndigo)
        let refresh = button(model.isChinese ? "刷新" : "Refresh", action: actions.refreshNews)
        var views: [NSView] = [makeHorizontalRow(left: heading, right: refresh)]

        if model.latestUpdates.isEmpty {
            let empty = label(model.isChinese ? "暂无缓存动态。" : "No cached updates yet.", font: .systemFont(ofSize: 12))
            empty.textColor = .secondaryLabelColor
            views.append(empty)
        } else {
            for update in model.latestUpdates {
                let link = linkButton(update.title, url: update.url)
                let source = label(update.subtitle ?? "", font: .systemFont(ofSize: 10))
                source.textColor = .tertiaryLabelColor
                let row = makeHorizontalRow(left: link, right: source)
                views.append(row)
            }
        }

        let docs = linkButton(model.isChinese ? "Codex 官方文档" : "Codex Documentation", url: CodexResource.docs)
        let changelog = linkButton(model.isChinese ? "完整更新日志" : "Full Changelog", url: CodexResource.changelog)
        let resources = NSStackView(views: [docs, changelog])
        resources.orientation = .horizontal
        resources.spacing = 14
        views.append(resources)
        return verticalSection(views, spacing: 10)
    }

    private func sectionHeading(symbol: String, title: String, color: NSColor) -> NSStackView {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
        let icon = NSImageView(image: image)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18)
        ])
        let titleLabel = label(title, font: .systemFont(ofSize: 16, weight: .semibold))
        let heading = NSStackView(views: [icon, titleLabel])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 8
        return heading
    }

    private func verticalSection(_ views: [NSView], spacing: CGFloat = 11) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        for view in stack.arrangedSubviews where view is NSStackView || view is NSTextField {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
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
