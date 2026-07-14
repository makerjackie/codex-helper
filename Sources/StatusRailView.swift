import SwiftUI

struct StatusRailView: View {
    let model: DashboardModel
    let dispatcher: DashboardActionDispatcher

    private var primary: DashboardUsageRow? { model.usageRows.first }
    private var primaryLevel: QuotaLevel { quotaLevel(for: primary?.remainingPercent) }

    var body: some View {
        HStack(spacing: 16) {
            QuotaGauge(remainingPercent: primary?.remainingPercent, size: 90, lineWidth: 7)

            Divider()
                .frame(height: 112)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(primary?.displayIdentity ?? "Codex")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    actionButton("arrow.clockwise", label: model.isChinese ? "刷新额度" : "Refresh quota") {
                        dispatcher.send(dispatcher.actions.refreshUsage)
                    }
                    actionButton("rectangle.on.rectangle", label: model.isChinese ? "打开主页面" : "Open dashboard") {
                        dispatcher.send(dispatcher.actions.showDashboard)
                    }
                    actionButton("xmark", label: model.isChinese ? "隐藏状态轨道" : "Hide status rail") {
                        dispatcher.send(dispatcher.actions.toggleQuotaWidget)
                    }
                }

                Text(primary?.detail ?? model.usageState)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let secondary = model.usageRows.dropFirst().first {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(quotaLevel(for: secondary.remainingPercent).color)
                            .frame(width: 8, height: 8)
                        Text(secondary.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(secondary.percentText)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                }

                Label(model.statusTitle, systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(model.autoRetryEnabled && model.accessibilityGranted ? Color.green : Color.orange)
                    .lineLimit(1)

                Text(model.usageFooter ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 410, height: 154)
        .quotaSurface(level: primaryLevel, cornerRadius: 26, floating: true)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isChinese ? "Codex 剩余额度状态轨道" : "Codex remaining quota status rail")
    }

    private func actionButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}
