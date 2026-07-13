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
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 246),
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
        let frameKey = "NSWindow Frame CodexHelperQuotaWidget"
        let hasSavedFrame = UserDefaults.standard.string(forKey: frameKey) != nil
        panel.setFrameAutosaveName("CodexHelperQuotaWidget")
        if !hasSavedFrame { positionPanel(panel) }
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }

    private func ensurePanelIsOnScreen() {
        guard let panel else { return }
        let minimumVisibleSize = NSSize(width: 80, height: 60)
        let isVisible = NSScreen.screens.contains { screen in
            let intersection = panel.frame.intersection(screen.visibleFrame)
            return intersection.width >= minimumVisibleSize.width && intersection.height >= minimumVisibleSize.height
        }
        if !isVisible { positionPanel(panel) }
    }

    private func makeContent(model: DashboardModel) -> NSView {
        let primary = model.usageRows.first
        let level = quotaLevel(for: primary?.remainingPercent)
        let surface = QuotaSurfaceView(level: level, cornerRadius: 24)

        let identity: String
        if let primary {
            identity = primary.planText.map { "\(primary.name) · \($0)" } ?? primary.name
        } else {
            identity = "Codex"
        }
        let title = label(identity.uppercased(), size: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let refresh = iconButton("arrow.clockwise", action: actions.refreshUsage, description: model.isChinese ? "刷新额度" : "Refresh quota")
        let open = iconButton("macwindow", action: actions.showDashboard, description: model.isChinese ? "打开主页面" : "Open dashboard")
        let close = iconButton("xmark", action: actions.toggleQuotaWidget, description: model.isChinese ? "隐藏小组件" : "Hide widget")
        let actionsRow = NSStackView(views: [refresh, open, close])
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 6
        let top = makeHorizontalRow(left: title, right: actionsRow)

        var arranged: [NSView] = [top]
        if let primary {
            let value = label(formatQuotaPercent(primary.remainingPercent), size: 44, weight: .medium, monospaced: true)
            let remaining = label(model.isChinese ? "剩余" : "left", size: 13, weight: .medium)
            remaining.textColor = .secondaryLabelColor
            let valueRow = NSStackView(views: [value, remaining])
            valueRow.orientation = .horizontal
            valueRow.alignment = .lastBaseline
            valueRow.spacing = 7

            let progress = QuotaProgressView(remainingPercent: primary.remainingPercent, level: level)
            let detail = label(primary.detail, size: 11, weight: .regular)
            detail.textColor = .secondaryLabelColor
            arranged += [valueRow, progress, detail]

            if let secondary = model.usageRows.dropFirst().first {
                let secondaryTitle = label(secondary.name, size: 12, weight: .medium)
                let secondaryValue = label(secondary.percentText, size: 12, weight: .semibold, monospaced: true)
                arranged.append(makeHorizontalRow(left: secondaryTitle, right: secondaryValue))
            }
        } else {
            let loading = label(model.usageState, size: 16, weight: .medium)
            arranged.append(loading)
        }

        let retryColor: NSColor = model.autoRetryEnabled && model.accessibilityGranted ? .systemGreen : .systemOrange
        let retryStatus = label("●  \(model.statusTitle)", size: 11, weight: .medium)
        retryStatus.textColor = retryColor
        arranged.append(retryStatus)

        if let footer = model.usageFooter {
            let footerLabel = label(footer, size: 10, weight: .regular)
            footerLabel.textColor = .tertiaryLabelColor
            arranged.append(footerLabel)
        }

        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: surface.bottomAnchor, constant: -18)
        ])
        for view in stack.arrangedSubviews where view is NSStackView || view is QuotaProgressView {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return surface
    }

    private func iconButton(_ symbol: String, action: Selector, description: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        let button = NSButton(image: image, target: actions.target, action: action)
        button.isBordered = false
        button.bezelStyle = .circular
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = description
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
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
