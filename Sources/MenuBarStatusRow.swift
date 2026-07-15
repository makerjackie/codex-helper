import SwiftUI

struct MenuBarStatusRow: View {
    let model: DashboardModel
    let dispatcher: DashboardActionDispatcher

    private var statusColor: Color {
        model.accessibilityGranted && model.autoRetryEnabled ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.autoRetryEnabled ? "bolt.shield.fill" : "bolt.slash.fill")
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.isChinese ? "自动重试" : "Auto Retry")
                    .font(.callout)
                    .bold()
                Text(model.statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(actionTitle, action: performAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }

    private var actionTitle: String {
        if !model.accessibilityGranted {
            return model.isChinese ? "授权" : "Allow"
        }
        if model.autoRetryEnabled {
            return model.isChinese ? "关闭" : "Turn Off"
        }
        return model.isChinese ? "开启" : "Turn On"
    }

    private func performAction() {
        let action = model.accessibilityGranted
            ? dispatcher.actions.toggleAutoRetry
            : dispatcher.actions.openAccessibility
        dispatcher.send(action)
    }
}
