import SwiftUI
import WidgetKit

private struct CodexHelperWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetQuotaSnapshot?
}

private struct CodexHelperWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexHelperWidgetEntry {
        CodexHelperWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexHelperWidgetEntry) -> Void) {
        completion(CodexHelperWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshotStore.load() ?? .preview
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexHelperWidgetEntry>) -> Void) {
        let now = Date()
        let entry = CodexHelperWidgetEntry(date: now, snapshot: WidgetSnapshotStore.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct CodexHelperWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexHelperWidgetEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                MediumQuotaView(snapshot: entry.snapshot)
            } else {
                SmallQuotaView(snapshot: entry.snapshot)
            }
        }
        .modifier(QuotaWidgetBackground(level: quotaLevel))
    }

    private var quotaLevel: WidgetQuotaLevel {
        WidgetQuotaLevel(percent: entry.snapshot?.windows.first?.remainingPercent)
    }
}

private struct SmallQuotaView: View {
    let snapshot: WidgetQuotaSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(window: primary)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 12) {
                QuotaRing(percent: primary?.remainingPercent, size: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(primary.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(isChinese ? "剩余" : "remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            ResetLine(window: primary)
        }
    }

    private var primary: WidgetQuotaWindow? { snapshot?.windows.first }
}

private struct MediumQuotaView: View {
    let snapshot: WidgetQuotaSnapshot?

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                WidgetHeader(window: primary)
                HStack(spacing: 12) {
                    QuotaRing(percent: primary?.remainingPercent, size: 70)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(primary.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                            .font(.system(size: 31, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(isChinese ? "剩余额度" : "remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ResetLine(window: primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array((snapshot?.windows ?? []).dropFirst().prefix(2)), id: \.id) { window in
                    QuotaDetailRow(window: window)
                }
                if (snapshot?.windows.count ?? 0) <= 1 {
                    Text(isChinese ? "额度会随 Codex 自动刷新" : "Quota refreshes with Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text(isChinese ? "可重置 \(snapshot?.resetCredits ?? 0) 次" : "\(snapshot?.resetCredits ?? 0) reset credits")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primary: WidgetQuotaWindow? { snapshot?.windows.first }
}

private struct WidgetHeader: View {
    let window: WidgetQuotaWindow?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal.fill")
                .font(.caption)
                .foregroundStyle(WidgetQuotaLevel(percent: window?.remainingPercent).color)
            Text(window?.name ?? "Codex")
                .font(.caption.weight(.semibold))
            if let plan = window?.planType, !plan.isEmpty {
                Text(plan.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct QuotaRing: View {
    let percent: Double?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.018, min((percent ?? 0) / 100, 1)))
                .stroke(
                    WidgetQuotaLevel(percent: percent).color,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(WidgetQuotaLevel(percent: percent).color.opacity(0.14))
                .frame(width: 16, height: 16)
            Circle()
                .fill(WidgetQuotaLevel(percent: percent).color)
                .frame(width: 6, height: 6)
        }
        .frame(width: size, height: size)
    }
}

private struct ResetLine: View {
    let window: WidgetQuotaWindow?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
            if let reset = window?.resetsAt, reset > Date() {
                Text(reset, style: .relative)
            } else {
                Text(isChinese ? "等待重置时间" : "Reset time unavailable")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct QuotaDetailRow: View {
    let window: WidgetQuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(WidgetQuotaLevel(percent: window.remainingPercent).color)
                        .frame(width: proxy.size.width * min(max(window.remainingPercent / 100, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }

    private var durationLabel: String {
        guard let minutes = window.windowDurationMins else {
            return isChinese ? "当前周期" : "Current window"
        }
        if minutes % 10080 == 0 {
            let weeks = minutes / 10080
            return isChinese ? "\(weeks) 周" : "\(weeks)w window"
        }
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return isChinese ? "\(days) 天" : "\(days)d window"
        }
        let hours = max(1, minutes / 60)
        return isChinese ? "\(hours) 小时" : "\(hours)h window"
    }
}

private struct QuotaWidgetBackground: ViewModifier {
    let level: WidgetQuotaLevel

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(for: .widget) { background }
        } else {
            content
                .padding(16)
                .background(background)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), level.color.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum WidgetQuotaLevel {
    case healthy
    case attention
    case critical
    case unavailable

    init(percent: Double?) {
        guard let percent else { self = .unavailable; return }
        if percent >= 50 { self = .healthy }
        else if percent >= 10 { self = .attention }
        else { self = .critical }
    }

    var color: Color {
        switch self {
        case .healthy: return Color(red: 0.13, green: 0.58, blue: 0.52)
        case .attention: return Color(red: 0.91, green: 0.57, blue: 0.15)
        case .critical: return Color(red: 0.91, green: 0.29, blue: 0.36)
        case .unavailable: return .secondary
        }
    }
}

private var isChinese: Bool {
    Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
}

private extension WidgetQuotaSnapshot {
    static var preview: WidgetQuotaSnapshot {
        WidgetQuotaSnapshot(
            windows: [
                WidgetQuotaWindow(
                    id: "codex-primary",
                    name: "Codex",
                    planType: "pro",
                    remainingPercent: 77,
                    windowDurationMins: 300,
                    resetsAt: Date().addingTimeInterval(78 * 60)
                ),
                WidgetQuotaWindow(
                    id: "codex-secondary",
                    name: "Codex",
                    planType: "pro",
                    remainingPercent: 42,
                    windowDurationMins: 10080,
                    resetsAt: Date().addingTimeInterval(2 * 24 * 60 * 60)
                )
            ],
            resetCredits: 1,
            fetchedAt: Date()
        )
    }
}

struct CodexHelperQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: codexHelperWidgetKind, provider: CodexHelperWidgetProvider()) { entry in
            CodexHelperWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Helper")
        .description("Codex remaining quota and reset time.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CodexHelperWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexHelperQuotaWidget()
    }
}
