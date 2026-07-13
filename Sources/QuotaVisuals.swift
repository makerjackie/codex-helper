import AppKit

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

func quotaAccentColor(for level: QuotaLevel) -> NSColor {
    switch level {
    case .healthy: return .systemTeal
    case .attention: return .systemOrange
    case .critical: return .systemPink
    case .unavailable: return .tertiaryLabelColor
    }
}

func formatQuotaPercent(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))%" : String(format: "%.1f%%", value)
}

func makeHorizontalRow(left: NSView, right: NSView) -> NSStackView {
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [left, spacer, right])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    return row
}

final class QuotaRingView: NSView {
    let remainingPercent: Double?
    let level: QuotaLevel
    let lineWidth: CGFloat

    init(remainingPercent: Double?, lineWidth: CGFloat = 9) {
        self.remainingPercent = remainingPercent
        self.level = quotaLevel(for: remainingPercent)
        self.lineWidth = lineWidth
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Codex quota")
        setAccessibilityValue(remainingPercent.map(formatQuotaPercent) ?? "Unavailable")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = lineWidth / 2 + 2
        let diameter = min(bounds.width, bounds.height) - inset * 2
        let ringRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        let track = NSBezierPath(ovalIn: ringRect)
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        track.stroke()

        if let remainingPercent {
            let value = min(max(remainingPercent, 0), 100) / 100
            let radius = diameter / 2
            let progress = NSBezierPath()
            progress.lineWidth = lineWidth
            progress.lineCapStyle = .round
            progress.appendArc(
                withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
                radius: radius,
                startAngle: 90,
                endAngle: 90 - 360 * value,
                clockwise: true
            )
            quotaAccentColor(for: level).setStroke()
            progress.stroke()
        }

        let valueText = remainingPercent.map(formatQuotaPercent) ?? "—"
        let fontSize = min(bounds.width, bounds.height) * 0.25
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let size = valueText.size(withAttributes: attributes)
        valueText.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

final class QuotaAccentDotView: NSView {
    let level: QuotaLevel

    init(level: QuotaLevel) {
        self.level = level
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 8),
            heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        quotaAccentColor(for: level).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

final class NeutralSurfaceView: NSVisualEffectView {
    init(cornerRadius: CGFloat, floating: Bool = false) {
        super.init(frame: .zero)
        material = floating ? .popover : .contentBackground
        blendingMode = floating ? .behindWindow : .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }
}

final class DashboardDividerView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.55).setFill()
        dirtyRect.fill()
    }
}

final class StatusPillLabel: NSTextField {
    let pillColor: NSColor

    init(text: String, color: NSColor) {
        self.pillColor = color
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = color
        lineBreakMode = .byTruncatingTail
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        pillColor.withAlphaComponent(0.10).setFill()
        background.fill()
        super.draw(dirtyRect)
    }
}
