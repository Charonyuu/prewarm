import AppKit

/// Draws the menu bar image. The bolt follows the menu bar's own colour; only
/// problems add colour, as a small dot in the corner.
enum MenuBarIcon {
    struct Input: Equatable {
        var status: MenuBarStatus
        var style: MenuBarStyle
        var percent: Int?
        var session: Double?
        var week: Double?
        var dark: Bool
        /// 0…1, for the warming pulse.
        var pulse: CGFloat = 1
    }

    static let brand = NSColor(red: 0.95, green: 0.42, blue: 0.11, alpha: 1)
    static let warning = NSColor(red: 0.95, green: 0.71, blue: 0.23, alpha: 1)
    static let danger = NSColor(red: 0.90, green: 0.27, blue: 0.21, alpha: 1)

    static func image(_ input: Input) -> NSImage {
        let ink = input.dark ? NSColor.white : NSColor.black
        let showBars = input.style == .bars && input.status != .setup
        let width: CGFloat = showBars ? 16 + 4 + 22 : 16
        let size = NSSize(width: width, height: 16)

        let image = NSImage(size: size, flipped: true) { _ in
            // Bolt on a 16-unit grid.
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 9.2, y: 1.2))
            bolt.line(to: NSPoint(x: 3.6, y: 9.1))
            bolt.line(to: NSPoint(x: 7.7, y: 9.1))
            bolt.line(to: NSPoint(x: 6.7, y: 14.8))
            bolt.line(to: NSPoint(x: 12.4, y: 6.8))
            bolt.line(to: NSPoint(x: 8.3, y: 6.8))
            bolt.close()
            bolt.lineJoinStyle = .round

            switch input.status {
            case .setup:
                ink.withAlphaComponent(0.85).setStroke()
                bolt.lineWidth = 1.2
                bolt.stroke()
            case .warming:
                brand.withAlphaComponent(0.45 + 0.55 * input.pulse).setFill()
                bolt.fill()
            default:
                ink.setFill()
                bolt.fill()
            }

            if let dot = dotColor(input.status) {
                let ring = NSBezierPath(ovalIn: NSRect(x: 10.5, y: 0.5, width: 6, height: 6))
                (input.dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                ring.fill()
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: 11.5, y: 1.5, width: 4, height: 4)).fill()
            }

            if showBars {
                drawBar(x: 20, y: 4, width: 22, value: input.session, ink: ink)
                drawBar(x: 20, y: 9.5, width: 22, value: input.week, ink: ink)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Prewarm"
        return image
    }

    private static func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, value: Double?, ink: NSColor) {
        let track = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 3.5), xRadius: 1.75, yRadius: 1.75)
        ink.withAlphaComponent(0.25).setFill()
        track.fill()
        guard let value else { return }
        let fill = max(3.5, width * CGFloat(min(max(value, 0), 100)) / 100)
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: fill, height: 3.5), xRadius: 1.75, yRadius: 1.75)
        (value >= 95 ? danger : value >= 80 ? warning : ink).setFill()
        bar.fill()
    }

    private static func dotColor(_ status: MenuBarStatus) -> NSColor? {
        switch status {
        case .nearLimit: return warning
        case .problem: return danger
        default: return nil
        }
    }
}
