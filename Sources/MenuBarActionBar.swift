import SwiftUI

struct MenuBarActionBar: View {
    let model: DashboardModel
    let dispatcher: DashboardActionDispatcher

    var body: some View {
        HStack(spacing: 9) {
            Button(
                model.isChinese ? "刷新" : "Refresh",
                systemImage: "arrow.clockwise",
                action: refresh
            )
            .buttonStyle(.bordered)

            Button(
                model.isChinese ? "打开主页面" : "Open Dashboard",
                systemImage: "rectangle.on.rectangle",
                action: openDashboard
            )
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 4)

            Button(model.isChinese ? "退出" : "Quit", action: quit)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .controlSize(.regular)
    }

    private func refresh() {
        dispatcher.send(dispatcher.actions.refreshUsage)
    }

    private func openDashboard() {
        dispatcher.send(dispatcher.actions.showDashboard)
    }

    private func quit() {
        dispatcher.send(dispatcher.actions.quitApp)
    }
}
