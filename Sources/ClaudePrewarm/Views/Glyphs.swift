import SwiftUI

/// Hand-drawn glyphs on a 16-unit grid, scaled to whatever frame they get.
struct GlyphShape: Shape {
    enum Kind { case bolt, overview, claude, codex, grok, agy }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        let ox = rect.midX - 8 * s
        let oy = rect.midY - 8 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()

        switch kind {
        case .bolt:
            path.move(to: p(9.2, 1.2))
            path.addLine(to: p(3.6, 9.1))
            path.addLine(to: p(7.7, 9.1))
            path.addLine(to: p(6.7, 14.8))
            path.addLine(to: p(12.4, 6.8))
            path.addLine(to: p(8.3, 6.8))
            path.closeSubpath()
        case .overview:
            for (x, y) in [(2.0, 2.0), (9.0, 2.0), (2.0, 9.0), (9.0, 9.0)] {
                path.addRoundedRect(in: CGRect(x: ox + x * s, y: oy + y * s, width: 5 * s, height: 5 * s),
                                    cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
            }
        case .claude:
            let segments: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (8, 1.8, 8, 5.4), (8, 10.6, 8, 14.2), (1.8, 8, 5.4, 8), (10.6, 8, 14.2, 8),
                (3.6, 3.6, 6.1, 6.1), (9.9, 9.9, 12.4, 12.4), (12.4, 3.6, 9.9, 6.1), (6.1, 9.9, 3.6, 12.4)
            ]
            for (x1, y1, x2, y2) in segments {
                path.move(to: p(x1, y1))
                path.addLine(to: p(x2, y2))
            }
        case .codex:
            path.addRoundedRect(in: CGRect(x: ox + 1.5 * s, y: oy + 2.5 * s, width: 13 * s, height: 11 * s),
                                cornerSize: CGSize(width: 3 * s, height: 3 * s))
            path.move(to: p(4.8, 6.3))
            path.addLine(to: p(6.8, 8.0))
            path.addLine(to: p(4.8, 9.7))
            path.move(to: p(8.6, 9.9))
            path.addLine(to: p(11.4, 9.9))
        case .grok:
            // An open ring with a slash through it.
            let start = -33.4 * Double.pi / 180
            let steps = 48
            for i in 0...steps {
                let angle = start - Double(i) / Double(steps) * (2 * Double.pi - 33.4 * Double.pi / 180)
                let point = p(8 + 5.3 * CGFloat(cos(angle)), 8 + 5.3 * CGFloat(sin(angle)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.move(to: p(3, 13))
            path.addLine(to: p(13.5, 2.5))
        case .agy:
            path.move(to: p(2.5, 13.5))
            path.addCurve(to: p(8, 3), control1: p(4.2, 8.7), control2: p(5.6, 3))
            path.addCurve(to: p(13.5, 13.5), control1: p(10.4, 3), control2: p(11.8, 8.7))
        }
        return path
    }
}

/// A tool's glyph in its own colour.
struct ProviderGlyph: View {
    let provider: Provider
    var size: CGFloat = 16

    var body: some View {
        GlyphShape(kind: kind)
            .stroke(Theme.tint(provider), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var kind: GlyphShape.Kind {
        switch provider {
        case .claude: return .claude
        case .codex: return .codex
        case .grok: return .grok
        case .agy: return .agy
        }
    }

    private var lineWidth: CGFloat {
        let base: CGFloat = provider == .codex ? 1.5 : provider == .agy ? 1.8 : 1.65
        return base * size / 16 * (size > 18 ? 0.92 : 1)
    }
}

/// The orange app mark: a rounded tile with a bolt.
struct AppMark: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.markGradient)
            .overlay(
                GlyphShape(kind: .bolt)
                    .fill(.white)
                    .frame(width: size * 0.54, height: size * 0.54)
            )
            .frame(width: size, height: size)
            .shadow(color: Theme.brand.opacity(0.32), radius: size * 0.1, y: size * 0.04)
            .accessibilityHidden(true)
    }
}
