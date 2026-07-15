import SwiftUI

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: DashboardModel
    let dispatcher: DashboardActionDispatcher

    private var primary: DashboardUsageRow? { model.usageRows.first }
    private var primaryLevel: QuotaLevel { quotaLevel(for: primary?.remainingPercent) }
    private var statusColor: Color {
        model.accessibilityGranted && model.autoRetryEnabled ? .green : .orange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                quotaOverview
                Divider().opacity(0.55)
                operations
                Divider().opacity(0.55)
                updates
                Divider().opacity(0.55)
                news
            }
            .padding(.horizontal, 38)
            .padding(.top, 34)
            .padding(.bottom, 38)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CodexPalette.canvas(colorScheme).ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 580)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Codex Helper")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text(model.isChinese
                    ? "安静地守着 Codex 的状态 · v\(model.version)"
                    : "A quiet status rail for Codex · v\(model.version)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            Label(model.statusTitle, systemImage: "circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(statusColor.opacity(0.10), in: Capsule())
        }
    }

    private var quotaOverview: some View {
        HStack(spacing: 22) {
            QuotaGauge(remainingPercent: primary?.remainingPercent, size: 128, lineWidth: 10)

            VStack(alignment: .leading, spacing: 8) {
                Text(model.isChinese ? "剩余额度" : "REMAINING QUOTA")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(primary?.displayIdentity ?? "Codex")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(primary?.detail ?? model.usageState)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                ForEach(Array(model.usageRows.dropFirst().enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(quotaLevel(for: row.remainingPercent).color)
                                .frame(width: 8, height: 8)
                            Text(row.displayIdentity)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 10)
                            Text(row.percentText)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        Text(row.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Button(model.showQuotaWidget
                    ? (model.isChinese ? "隐藏悬浮轨道" : "Hide Floating Rail")
                    : (model.isChinese ? "显示悬浮轨道" : "Show Floating Rail")) {
                    dispatcher.send(dispatcher.actions.toggleQuotaWidget)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryLevel.color)

                Button(model.isChinese ? "添加 macOS 小组件…" : "Add macOS Widget…") {
                    dispatcher.send(dispatcher.actions.showNativeWidgetHelp)
                }
                .buttonStyle(.bordered)

                Button(model.isChinese ? "刷新" : "Refresh") {
                    dispatcher.send(dispatcher.actions.refreshUsage)
                }
                .buttonStyle(.bordered)

                if let footer = model.usageFooter {
                    Text(footer)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(24)
        .quotaSurface(level: primaryLevel, cornerRadius: 22)
    }

    private var operations: some View {
        HStack(alignment: .top, spacing: 28) {
            retrySection
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            preferencesSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var retrySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading(model.isChinese ? "自动重试" : "Auto Retry", symbol: "arrow.triangle.2.circlepath", color: .purple)
            Text(model.statusTitle)
                .font(.system(size: 14, weight: .medium))
            Text(model.statusDetail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(
                model.isChinese ? "启用自动重试" : "Enable Auto Retry",
                isOn: toggleBinding(model.autoRetryEnabled, selector: dispatcher.actions.toggleAutoRetry)
            )
            .toggleStyle(.checkbox)
            Button(model.isChinese ? "运行端到端测试…" : "Run End-to-End Test…") {
                dispatcher.send(dispatcher.actions.testAutoRetry)
            }
            .buttonStyle(.bordered)
            .disabled(!model.accessibilityGranted || !model.autoRetryEnabled)

            if !model.accessibilityGranted {
                Button(model.isChinese ? "授予辅助功能权限…" : "Allow Accessibility…") {
                    dispatcher.send(dispatcher.actions.openAccessibility)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading(model.isChinese ? "偏好设置" : "Preferences", symbol: "slider.horizontal.3", color: .teal)
            Toggle(
                model.isChinese ? "登录时启动" : "Launch at login",
                isOn: toggleBinding(model.launchAtLogin, selector: dispatcher.actions.toggleLaunchAtLogin)
            )
            .toggleStyle(.checkbox)
            Toggle(
                model.isChinese ? "菜单栏显示剩余额度" : "Show quota in menu bar",
                isOn: toggleBinding(model.showQuotaInMenuBar, selector: dispatcher.actions.toggleMenuBarQuota)
            )
            .toggleStyle(.checkbox)
            Toggle(
                model.isChinese ? "显示 Spark 额度" : "Show Spark quota",
                isOn: toggleBinding(model.showSparkQuota, selector: dispatcher.actions.toggleSparkQuota)
            )
            .toggleStyle(.checkbox)

            HStack {
                Text(model.isChinese ? "界面与续跑语言" : "Interface and retry language")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: languageBinding) {
                    Text(model.isChinese ? "自动" : "Automatic").tag(0)
                    Text("English").tag(1)
                    Text("简体中文").tag(2)
                }
                .labelsHidden()
                .frame(width: 116)
            }

            HStack(spacing: 8) {
                Button(model.isChinese ? "登录项…" : "Login Items…") {
                    dispatcher.send(dispatcher.actions.openLoginItems)
                }
                Button(model.isChinese ? "日志" : "Logs") {
                    dispatcher.send(dispatcher.actions.openLogs)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var updates: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeading(model.isChinese ? "应用更新" : "App Updates", symbol: "arrow.down.circle", color: .blue)
                Text(model.updatesState)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                model.isChinese ? "自动下载" : "Auto-download",
                isOn: toggleBinding(model.automaticUpdates, selector: dispatcher.actions.toggleAutomaticUpdates)
            )
            .toggleStyle(.checkbox)
            Button(model.updateActionTitle) {
                dispatcher.send(dispatcher.actions.performUpdate)
            }
            .buttonStyle(.bordered)
            .disabled(!model.updateActionEnabled)
        }
    }

    private var news: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeading(model.isChinese ? "Codex 动态" : "Codex Updates", symbol: "newspaper", color: .indigo)
                Spacer()
                Button(model.isChinese ? "刷新" : "Refresh") {
                    dispatcher.send(dispatcher.actions.refreshNews)
                }
                .buttonStyle(.bordered)
            }

            if model.latestUpdates.isEmpty {
                Text(model.isChinese ? "暂无缓存动态。" : "No cached updates yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.latestUpdates.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Button(item.title) { dispatcher.open(item.url) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        Spacer()
                        Text(item.subtitle ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 16) {
                Link(model.isChinese ? "Codex 官方文档" : "Codex Documentation", destination: CodexResource.docs)
                Link(model.isChinese ? "完整更新日志" : "Full Changelog", destination: CodexResource.changelog)
            }
            .font(.system(size: 12))
        }
    }

    private func sectionHeading(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.monochrome)
            .labelStyle(ColoredIconLabelStyle(color: color))
    }

    private func toggleBinding(_ value: Bool, selector: Selector) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { dispatcher.sendToggle(selector, isOn: $0) }
        )
    }

    private var languageBinding: Binding<Int> {
        Binding(
            get: { model.languageIndex },
            set: { dispatcher.sendLanguage(index: $0) }
        )
    }
}

private struct ColoredIconLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
