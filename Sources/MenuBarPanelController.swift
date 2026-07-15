import AppKit
import SwiftUI

final class MenuBarPanelController {
    private let actions: DashboardActions
    private let popover = NSPopover()
    private var hostingController: NSHostingController<MenuBarPanelView>?
    private var latestModel: DashboardModel?

    init(actions: DashboardActions) {
        self.actions = actions
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(
            width: MenuBarPanelMetrics.width,
            height: MenuBarPanelMetrics.height
        )
    }

    func toggle(relativeTo button: NSStatusBarButton, model: DashboardModel) {
        if popover.isShown {
            close()
            return
        }

        show(relativeTo: button, model: model)
    }

    private func show(relativeTo button: NSStatusBarButton, model: DashboardModel) {
        update(model: model)
        configureHostingControllerIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover.performClose(nil)
    }

    func update(model: DashboardModel) {
        latestModel = model
        guard let hostingController else { return }
        hostingController.rootView = makeRootView(model: model)
    }

    private func configureHostingControllerIfNeeded() {
        guard hostingController == nil, let latestModel else { return }
        let controller = NSHostingController(rootView: makeRootView(model: latestModel))
        controller.view.frame = NSRect(
            x: 0,
            y: 0,
            width: MenuBarPanelMetrics.width,
            height: MenuBarPanelMetrics.height
        )
        popover.contentViewController = controller
        hostingController = controller
    }

    private func makeRootView(model: DashboardModel) -> MenuBarPanelView {
        MenuBarPanelView(
            model: model,
            dispatcher: DashboardActionDispatcher(actions: actions)
        )
    }
}
