import SwiftUI

struct MenuBarPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: DashboardModel
    let dispatcher: DashboardActionDispatcher

    var body: some View {
        VStack(spacing: MenuBarPanelMetrics.sectionSpacing) {
            MenuBarPanelHeader(model: model)
            MenuBarQuotaCard(model: model)
            MenuBarStatusRow(model: model, dispatcher: dispatcher)
            Divider()
            MenuBarActionBar(model: model, dispatcher: dispatcher)
        }
        .padding(MenuBarPanelMetrics.padding)
        .frame(
            width: MenuBarPanelMetrics.width,
            height: MenuBarPanelMetrics.height,
            alignment: .top
        )
        .background(CodexPalette.canvas(colorScheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isChinese ? "Codex 菜单栏概览" : "Codex menu bar overview")
    }
}
