import AppKit

final class QuotaWidgetController {
    private let actions: DashboardActions
    private var panel: NSPanel?

    init(actions: DashboardActions) {
        self.actions = actions
    }

    func show(model: DashboardModel) {
        if panel == nil {
            panel = makePanel()
        }
        update(model: model)
        ensurePanelIsOnScreen()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func update(model: DashboardModel) {
        guard let panel else { return }
        panel.contentView = makeContent(model: model)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 154),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        let frameKey = "NSWindow Frame CodexHelperQuotaWidgetRail"
        let hasSavedFrame = UserDefaults.standard.string(forKey: frameKey) != nil
        panel.setFrameAutosaveName("CodexHelperQuotaWidgetRail")
        if !hasSavedFrame { positionPanel(panel) }
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.maxY - panel.frame.height - 24
        ))
    }

    private func ensurePanelIsOnScreen() {
        guard let panel else { return }
        let isVisible = NSScreen.screens.contains { screen in
            let intersection = panel.frame.intersection(screen.visibleFrame)
            return intersection.width >= 100 && intersection.height >= 70
        }
        if !isVisible { positionPanel(panel) }
    }

    private func makeContent(model: DashboardModel) -> NSView {
        let primary = model.usageRows.first
        let primaryLevel = quotaLevel(for: primary?.remainingPercent)
        let surface = NeutralSurfaceView(cornerRadius: 26, floating: true)

        let ring = QuotaRingView(remainingPercent: primary?.remainingPercent, lineWidth: 8)
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 92),
            ring.heightAnchor.constraint(equalToConstant: 92)
        ])

        let identity = primary?.displayIdentity ?? "Codex"
        let title = label(identity, size: 13, weight: .semibold)

        let refresh = iconButton("arrow.clockwise", action: actions.refreshUsage, description: model.isChinese ? "刷新额度" : "Refresh quota")
        let open = iconButton("rectangle.on.rectangle", action: actions.showDashboard, description: model.isChinese ? "打开主页面" : "Open dashboard")
        let close = iconButton("xmark", action: actions.toggleQuotaWidget, description: model.isChinese ? "隐藏状态轨道" : "Hide status rail")
        let buttons = NSStackView(views: [refresh, open, close])
        buttons.orientation = .horizontal
        buttons.spacing = 3
        let heading = makeHorizontalRow(left: title, right: buttons)

        let reset = label(primary?.detail ?? model.usageState, size: 11, weight: .regular)
        reset.textColor = .secondaryLabelColor

        var details: [NSView] = [heading, reset]
        if let secondary = model.usageRows.dropFirst().first {
            let dot = QuotaAccentDotView(level: quotaLevel(for: secondary.remainingPercent))
            let secondaryName = label(secondary.name, size: 11, weight: .medium)
            let secondaryValue = label(secondary.percentText, size: 11, weight: .semibold, monospaced: true)
            let secondaryUsageLabel = NSStackView(views: [dot, secondaryName])
            secondaryUsageLabel.orientation = .horizontal
            secondaryUsageLabel.alignment = .centerY
            secondaryUsageLabel.spacing = 6
            details.append(makeHorizontalRow(left: secondaryUsageLabel, right: secondaryValue))
        }

        let retryReady = model.autoRetryEnabled && model.accessibilityGranted
        let statusColor: NSColor = retryReady ? .systemGreen : .systemOrange
        let statusText = label("●  \(model.statusTitle)", size: 10, weight: .medium)
        statusText.textColor = statusColor
        let footer = label(model.usageFooter ?? "", size: 9, weight: .regular)
        footer.textColor = .tertiaryLabelColor
        details += [statusText, footer]

        let detailStack = NSStackView(views: details)
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 7

        let separator = DashboardDividerView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let layout = NSStackView(views: [ring, separator, detailStack])
        layout.orientation = .horizontal
        layout.alignment = .centerY
        layout.spacing = 16
        layout.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18),
            layout.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
            layout.topAnchor.constraint(equalTo: surface.topAnchor, constant: 14),
            layout.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -14),
            separator.heightAnchor.constraint(equalTo: layout.heightAnchor, constant: -12),
            detailStack.widthAnchor.constraint(equalTo: layout.widthAnchor, constant: -126)
        ])
        for view in detailStack.arrangedSubviews where view is NSStackView {
            view.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        }

        surface.setAccessibilityLabel(model.isChinese ? "Codex 剩余额度状态轨道" : "Codex remaining quota status rail")
        surface.setAccessibilityHelp(primaryLevel == .critical ? (model.isChinese ? "额度接近用尽" : "Quota is nearly exhausted") : nil)
        return surface
    }

    private func iconButton(_ symbol: String, action: Selector, description: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        let button = NSButton(image: image, target: actions.target, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = description
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
