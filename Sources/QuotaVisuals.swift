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

private extension QuotaLevel {
    var accentColor: NSColor {
        switch self {
        case .healthy: return .systemBlue
        case .attention: return .systemOrange
        case .critical: return .systemRed
        case .unavailable: return .tertiaryLabelColor
        }
    }

    func gradientColors(dark: Bool) -> [NSColor] {
        if dark {
            switch self {
            case .healthy:
                return [
                    NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.34, alpha: 1),
                    NSColor(calibratedRed: 0.09, green: 0.28, blue: 0.25, alpha: 1)
                ]
            case .attention:
                return [
                    NSColor(calibratedRed: 0.32, green: 0.24, blue: 0.09, alpha: 1),
                    NSColor(calibratedRed: 0.34, green: 0.16, blue: 0.09, alpha: 1)
                ]
            case .critical:
                return [
                    NSColor(calibratedRed: 0.34, green: 0.12, blue: 0.11, alpha: 1),
                    NSColor(calibratedRed: 0.31, green: 0.10, blue: 0.22, alpha: 1)
                ]
            case .unavailable:
                return [NSColor(calibratedWhite: 0.16, alpha: 1), NSColor(calibratedWhite: 0.20, alpha: 1)]
            }
        }

        switch self {
        case .healthy:
            return [
                NSColor(calibratedRed: 0.86, green: 0.94, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.89, green: 0.98, blue: 0.93, alpha: 1)
            ]
        case .attention:
            return [
                NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.80, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.81, alpha: 1)
            ]
        case .critical:
            return [
                NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.86, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.91, alpha: 1)
            ]
        case .unavailable:
            return [NSColor(calibratedWhite: 0.95, alpha: 1), NSColor(calibratedWhite: 0.91, alpha: 1)]
        }
    }
}

final class QuotaSurfaceView: NSView {
    var level: QuotaLevel {
        didSet { needsDisplay = true }
    }
    let cornerRadius: CGFloat

    init(level: QuotaLevel, cornerRadius: CGFloat = 22) {
        self.level = level
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
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
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: level.gradientColors(dark: dark))?.draw(in: path, angle: -18)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(dark ? 0.55 : 0.38).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class QuotaProgressView: NSView {
    var remainingPercent: Double {
        didSet { needsDisplay = true }
    }
    var level: QuotaLevel {
        didSet { needsDisplay = true }
    }

    init(remainingPercent: Double, level: QuotaLevel) {
        self.remainingPercent = remainingPercent
        self.level = level
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 7).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        track.fill()

        let value = min(max(remainingPercent, 0), 100) / 100
        let fillRect = NSRect(x: 0, y: 0, width: bounds.width * value, height: bounds.height)
        guard fillRect.width > 0 else { return }
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        level.accentColor.setFill()
        fill.fill()
    }
}

final class DashboardSurfaceView: NSView {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
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
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class DashboardDividerView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.65).setFill()
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
        pillColor.withAlphaComponent(0.12).setFill()
        background.fill()
        super.draw(dirtyRect)
    }
}
