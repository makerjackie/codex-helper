import Foundation

enum QuotaLevel: Equatable {
    case healthy
    case attention
    case critical
    case unavailable
}

func quotaLevel(for remainingPercent: Double?) -> QuotaLevel {
    guard let remainingPercent else { return .unavailable }
    if remainingPercent < 10 { return .critical }
    if remainingPercent < 50 { return .attention }
    return .healthy
}

func formatQuotaPercent(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))%" : String(format: "%.1f%%", value)
}
