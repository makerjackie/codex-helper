import SwiftUI

struct MenuBarQuotaCard: View {
    let model: DashboardModel

    private var primary: DashboardUsageRow? { model.usageRows.first }
    private var level: QuotaLevel { quotaLevel(for: primary?.remainingPercent) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                QuotaGauge(
                    remainingPercent: primary?.remainingPercent,
                    size: 112,
                    lineWidth: 9
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(primary?.displayIdentity ?? "Codex")
                        .font(.title3)
                        .bold()
                        .lineLimit(1)
                    Text(model.isChinese ? "官方通用额度" : "Official general quota")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let resetAt = model.primaryResetAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let countdown = formatResetCountdown(
                                until: resetAt,
                                from: context.date,
                                isChinese: model.isChinese
                            )
                            Label(
                                countdown,
                                systemImage: "clock"
                            )
                            .font(.body.monospacedDigit())
                            .foregroundStyle(level.color)
                            .accessibilityLabel(model.isChinese ? "距离重置" : "Time until reset")
                            .accessibilityValue(countdown)
                        }
                    } else {
                        Label(
                            model.isChinese ? "重置时间暂不可用" : "Reset time unavailable",
                            systemImage: "clock.badge.questionmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Label(
                    model.isChinese ? "剩余重置机会" : "Reset credits",
                    systemImage: "arrow.counterclockwise.circle"
                )
                .foregroundStyle(.secondary)
                Spacer()
                Text(creditsText)
                    .bold()
                    .monospacedDigit()
            }
            .font(.callout)
        }
        .padding(MenuBarPanelMetrics.cardPadding)
        .quotaSurface(level: level, cornerRadius: MenuBarPanelMetrics.cornerRadius)
    }

    private var creditsText: String {
        guard let credits = model.resetCredits else { return "—" }
        return model.isChinese ? "\(credits) 次" : "\(credits)"
    }
}
