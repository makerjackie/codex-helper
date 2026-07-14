import SwiftUI

extension QuotaLevel {
    var color: Color {
        switch self {
        case .healthy: return Color(red: 0.08, green: 0.61, blue: 0.53)
        case .attention: return Color(red: 0.94, green: 0.57, blue: 0.16)
        case .critical: return Color(red: 0.91, green: 0.24, blue: 0.34)
        case .unavailable: return .secondary
        }
    }
}

enum CodexPalette {
    static func canvas(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.062, blue: 0.066)
            : Color(red: 0.965, green: 0.976, blue: 0.972)
    }

    static func surface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.105, blue: 0.11)
            : Color(red: 1, green: 1, blue: 1)
    }

    static func floatingSurface(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.085, green: 0.095, blue: 0.10)
            : Color(red: 0.995, green: 0.998, blue: 0.995)
    }

    static func hairline(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }
}

struct QuotaGauge: View {
    let remainingPercent: Double?
    let size: CGFloat
    let lineWidth: CGFloat
    var showsValue = true

    private var level: QuotaLevel { quotaLevel(for: remainingPercent) }
    private var progress: Double {
        min(max((remainingPercent ?? 0) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.075), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: remainingPercent == nil ? 0 : max(0.012, progress))
                .stroke(
                    level.color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsValue {
                Text(remainingPercent.map(formatQuotaPercent) ?? "—")
                    .font(.system(size: size * 0.25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex quota")
        .accessibilityValue(remainingPercent.map(formatQuotaPercent) ?? "Unavailable")
    }
}

struct QuotaSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let level: QuotaLevel
    let cornerRadius: CGFloat
    let floating: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(floating ? CodexPalette.floatingSurface(colorScheme) : CodexPalette.surface(colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, level.color.opacity(floating ? 0.11 : 0.045)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(CodexPalette.hairline(colorScheme), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func quotaSurface(level: QuotaLevel, cornerRadius: CGFloat, floating: Bool = false) -> some View {
        modifier(QuotaSurface(level: level, cornerRadius: cornerRadius, floating: floating))
    }
}
