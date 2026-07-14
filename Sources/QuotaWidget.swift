import AppKit
import SwiftUI

final class QuotaWidgetController {
    private let actions: DashboardActions
    private var panel: NSPanel?
    private var hostingView: TransparentHostingView<StatusRailView>?

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
        let rootView = StatusRailView(
            model: model,
            dispatcher: DashboardActionDispatcher(actions: actions)
        )
        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = TransparentHostingView(rootView: rootView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        panel.invalidateShadow()
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
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}
