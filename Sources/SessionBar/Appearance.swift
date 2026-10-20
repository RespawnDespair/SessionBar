import AppKit

/// Colours and animation curves shared by the Touch Bar and the menu bar icon.
enum Appearance {
    static let green = NSColor(srgbRed: 0.30, green: 0.85, blue: 0.45, alpha: 1)
    static let orange = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.10, alpha: 1)
    static let grey = NSColor(white: 0.55, alpha: 1)

    static func color(for display: SessionDisplay) -> NSColor {
        switch display {
        case .idle, .working: green
        case .attention, .unseen: orange
        }
    }

    /// Dot opacity at time `t` (seconds): working breathes, attention blinks.
    static func alpha(for display: SessionDisplay, at t: TimeInterval) -> CGFloat {
        switch display {
        case .idle, .unseen:
            return 1
        case .working:
            return 0.35 + 0.65 * CGFloat(0.5 + 0.5 * sin(t * 2 * .pi / 1.6))
        case .attention:
            return t.truncatingRemainder(dividingBy: 0.8) < 0.5 ? 1 : 0.12
        }
    }

    static func drawDot(in rect: NSRect, display: SessionDisplay, at t: TimeInterval) {
        color(for: display).withAlphaComponent(alpha(for: display, at: t)).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    /// A row of dots, one per session, for the Control Strip and the menu bar.
    static func summaryImage(_ displays: [SessionDisplay], at t: TimeInterval, height: CGFloat,
                             dot: CGFloat, maxDots: Int) -> NSImage {
        let shown = Array(displays.prefix(maxDots))
        let gap: CGFloat = dot * 0.5
        let count = max(shown.count, 1)
        let width = CGFloat(count) * dot + CGFloat(count - 1) * gap
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let y = (height - dot) / 2
            if shown.isEmpty {
                let ring = NSBezierPath(ovalIn: NSRect(x: 0.75, y: y + 0.75, width: dot - 1.5, height: dot - 1.5))
                ring.lineWidth = 1.5
                grey.setStroke()
                ring.stroke()
            }
            for (index, display) in shown.enumerated() {
                let x = CGFloat(index) * (dot + gap)
                drawDot(in: NSRect(x: x, y: y, width: dot, height: dot), display: display, at: t)
            }
            return true
        }
    }
}
