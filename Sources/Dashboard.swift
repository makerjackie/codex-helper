import AppKit
import SwiftUI

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
    let showNativeWidgetHelp: Selector
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

struct DashboardActionDispatcher {
    let actions: DashboardActions

    func send(_ selector: Selector, sender: Any? = nil) {
        NSApp.sendAction(selector, to: actions.target, from: sender)
    }

    func sendToggle(_ selector: Selector, isOn: Bool) {
        let sender = NSButton()
        sender.state = isOn ? .on : .off
        send(selector, sender: sender)
    }

    func sendLanguage(index: Int) {
        let sender = NSPopUpButton()
        sender.addItems(withTitles: ["Automatic", "English", "简体中文"])
        sender.selectItem(at: index)
        send(actions.changeLanguage, sender: sender)
    }

    func open(_ url: URL) {
        let sender = NSButton()
        sender.identifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        send(actions.openLink, sender: sender)
    }
}

final class DashboardController {
    private let actions: DashboardActions
    private var window: NSWindow?
    private var hostingView: NSHostingView<DashboardView>?

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
        let rootView = DashboardView(
            model: model,
            dispatcher: DashboardActionDispatcher(actions: actions)
        )
        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            window.contentView = hostingView
            self.hostingView = hostingView
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
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .hidden
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = .windowBackgroundColor
        return window
    }
}
