import AppKit
import SwiftUI

/// Spacera's look: warm paper, muted mid-century colours taken from the app icon, and New York (the system serif)
/// for headline numbers. Native chrome (sidebar, toolbar, controls) is left to the system.
enum Theme {
    // Surfaces and text. Each has a light and a dark value.
    static let paper = Color(light: 0xF5F0E6, dark: 0x1D1A17)
    static let surface = Color(light: 0xFBF8F2, dark: 0x27231F)
    static let ink = Color(light: 0x2A2521, dark: 0xEEE7DB)
    static let inkSecondary = Color(light: 0x786E64, dark: 0xA69C90)
    static let rule = Color(light: 0xE3D9C8, dark: 0x3A342D)
    /// Matches AccentColor in the asset catalog, which tints native controls.
    static let accent = Color(light: 0xB0563A, dark: 0xD27C5D)

    // Data colours, muted so that many of them can sit side by side.
    static let rust = Color(light: 0xC0694E, dark: 0xCF7A5E)
    static let mustard = Color(light: 0xD1A247, dark: 0xD9AE58)
    static let sage = Color(light: 0x8BA17D, dark: 0x97AD89)
    static let slate = Color(light: 0x6A8BA6, dark: 0x7D9DB7)
    static let mauve = Color(light: 0x9F7B93, dark: 0xB08DA4)
    static let teal = Color(light: 0x5E8B80, dark: 0x6F9C91)
    static let peach = Color(light: 0xE0A784, dark: 0xE3B091)
    static let walnut = Color(light: 0x8E7058, dark: 0xA3846B)
    static let stone = Color(light: 0xB7AB99, dark: 0x6E665B)

    /// Colours for the top-level items in charts, in order.
    static let series: [Color] = [slate, rust, sage, mustard, mauve, teal, peach, walnut]

    static func seriesColor(_ index: Int) -> Color { series[index % series.count] }

    /// Large serif numbers and headings.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let pageTitle = display(30)
    static let sectionTitle = display(19)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension View {
    /// The paper background used behind each screen's content. Fills the space it's given.
    func paperBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper.ignoresSafeArea())
    }

    /// A section heading in the serif, with an optional trailing control.
    func sectionHeading() -> some View {
        font(Theme.sectionTitle).foregroundStyle(Theme.ink)
    }
}

/// A secondary button that sits quietly on the paper: a solid surface, a warm outline, and ink text.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(configuration.isPressed ? Theme.rule : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.rule.mix(with: Theme.ink, by: 0.15)))
            .contentShape(Capsule())
    }
}

/// A hairline divider in the warm rule colour.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: 1)
    }
}

extension Color {
    /// The colour darkened (or lightened, in dark mode) toward the ink, so it reads as text on paper.
    var readable: Color { mix(with: Theme.ink, by: 0.4) }
}
