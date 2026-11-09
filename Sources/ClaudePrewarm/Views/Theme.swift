import AppKit
import SwiftUI

/// One palette, two schemes. Every colour used by the UI comes from here.
/// One brand orange; each tool only tints its own small glyph.
enum Theme {
    static let window = Color(light: Color(hex: 0xF3F2F0), dark: Color(hex: 0x232325))
    static let card = Color(light: .white, dark: Color(hex: 0x2E2E31))
    static let sidebar = Color(light: Color(hex: 0xEAE8E5), dark: Color(hex: 0x2A2A2D))
    static let title = Color(light: Color(hex: 0x1D1D1F), dark: Color(hex: 0xF2F2F4))
    static let label = Color(light: Color(hex: 0x5F5F66), dark: Color(hex: 0xA6A6AD))
    static let line = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.10))
    static let track = Color(light: Color(hex: 0xE6E4E1), dark: Color(hex: 0x3C3C41))
    static let hover = Color(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.07))
    static let chip = Color(light: Color(hex: 0xEAE8E5), dark: Color(hex: 0x3A3A3F))
    static let chipText = Color(light: Color(hex: 0x45454B), dark: Color(hex: 0xD6D6DC))
    static let tabOn = Color(light: .white, dark: Color(hex: 0x3E3E43))

    static let accent = Color(hex: 0xC24A0C)
    static let accentPressed = Color(hex: 0xA63F0A)
    static let brand = Color(hex: 0xF26B1D)
    static let meter = Color(light: Color(hex: 0xF26B1D), dark: Color(hex: 0xFF7A2E))
    static let markGradient = LinearGradient(
        colors: [Color(hex: 0xFA8C3D), Color(hex: 0xE5551A)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let warning = Color(light: Color(hex: 0xD08C00), dark: Color(hex: 0xF2B43A))
    static let warningText = Color(light: Color(hex: 0x8A5A00), dark: Color(hex: 0xF4C766))
    static let warningBackground = Color(light: Color(hex: 0xFFF4D6), dark: Color(hex: 0xF2B43A).opacity(0.14))
    static let danger = Color(light: Color(hex: 0xD23B2A), dark: Color(hex: 0xFF6B5E))
    static let dangerText = Color(light: Color(hex: 0xB42318), dark: Color(hex: 0xFF8F86))
    static let dangerBackground = Color(light: Color(hex: 0xFDECEA), dark: Color(hex: 0xFF6B5E).opacity(0.14))
    static let good = Color(light: Color(hex: 0x1F9D55), dark: Color(hex: 0x3DD07A))
    static let goodText = Color(light: Color(hex: 0x177A42), dark: Color(hex: 0x62DB93))

    static func tint(_ provider: Provider) -> Color {
        switch provider {
        case .claude: return Color(hex: 0xD97757)
        case .codex: return Color(hex: 0x10A37F)
        case .grok: return title
        case .agy: return Color(hex: 0x3B7CF0)
        }
    }

    /// Meter colour: amber from 80%, red from 95%.
    static func meterColor(_ percent: Double?) -> Color {
        guard let percent else { return meter }
        if percent >= 95 { return danger }
        if percent >= 80 { return warning }
        return meter
    }
}

extension Color {
    /// Resolves per appearance, so one declaration covers both schemes.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
