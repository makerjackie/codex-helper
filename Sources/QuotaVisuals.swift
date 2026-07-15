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

func formatCompactResetDistance(
    until reset: Date,
    from now: Date = Date(),
    isChinese: Bool
) -> String {
    let totalMinutes = max(Int(ceil(reset.timeIntervalSince(now) / 60)), 0)
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        return isChinese ? "\(days)天\(hours)时" : "\(days)d \(hours)h"
    }
    if hours > 0 {
        return String(format: "%d:%02d", hours, minutes)
    }
    return isChinese ? "\(minutes)分" : "\(minutes)m"
}

func formatResetCountdown(
    until reset: Date,
    from now: Date = Date(),
    isChinese: Bool
) -> String {
    let totalSeconds = max(Int(reset.timeIntervalSince(now)), 0)
    let days = totalSeconds / (24 * 60 * 60)
    let hours = (totalSeconds % (24 * 60 * 60)) / (60 * 60)
    let minutes = (totalSeconds % (60 * 60)) / 60
    let seconds = totalSeconds % 60

    if days > 0 {
        return isChinese ? "\(days)天 \(hours)小时 \(minutes)分" : "\(days)d \(hours)h \(minutes)m"
    }
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}
