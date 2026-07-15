import SwiftUI

struct MenuBarPanelHeader: View {
    let model: DashboardModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: [.teal, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 13)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isChinese ? "Codex 概览" : "Codex Overview")
                    .font(.headline)
                Label(statusText, systemImage: model.usageIsRefreshing ? "arrow.clockwise" : "circle.fill")
                    .font(.caption)
                    .foregroundStyle(model.usageIsRefreshing ? Color.orange : Color.green)
            }
            Spacer(minLength: 8)
            Text("v\(model.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusText: String {
        if model.usageIsRefreshing {
            return model.isChinese ? "正在刷新" : "Refreshing"
        }
        if let updatedAt = model.usageUpdatedAt {
            let time = updatedAt.formatted(date: .omitted, time: .shortened)
            return model.isChinese ? "更新于 \(time)" : "Updated \(time)"
        }
        return model.isChinese ? "每 5 分钟自动更新" : "Updates every 5 minutes"
    }
}
