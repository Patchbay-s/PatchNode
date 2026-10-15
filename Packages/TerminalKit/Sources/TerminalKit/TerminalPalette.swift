import Foundation

/// The 16 ANSI colors for a light or a dark background: the default xterm
/// palette is made for black, and its yellow or white text disappears on a
/// light background. Components are 0…255.
public struct TerminalPalette: Sendable, Equatable {
    public struct RGB: Sendable, Equatable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(_ hex: UInt32) {
            red = UInt8((hex >> 16) & 0xFF)
            green = UInt8((hex >> 8) & 0xFF)
            blue = UInt8(hex & 0xFF)
        }

        /// Relative luminance (WCAG), 0…1.
        public var luminance: Double {
            func linear(_ c: UInt8) -> Double {
                let v = Double(c) / 255
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    public let foreground: RGB
    public let background: RGB
    /// black, red, green, yellow, blue, magenta, cyan, white, then the bright ones.
    public let ansi: [RGB]

    /// Contrast ratio (WCAG) of two colors, 1…21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    public static let dark = TerminalPalette(
        foreground: RGB(0xE6E6E6),
        background: RGB(0x1C1C1E),
        ansi: [
            0x3A3A3C, 0xFF6B6B, 0x5FD77A, 0xF2C94C, 0x6CA8FF, 0xD68CFF, 0x5CD6E0, 0xD0D0D0,
            0x6E6E73, 0xFF8A8A, 0x7FE89A, 0xFFE07A, 0x8FBFFF, 0xE5A8FF, 0x84E5EC, 0xFFFFFF,
        ].map(RGB.init)
    )

    /// Every color readable on white (at least 3:1, ANSI "white" included,
    /// which becomes a mid gray).
    public static let light = TerminalPalette(
        foreground: RGB(0x1C1C1E),
        background: RGB(0xFFFFFF),
        ansi: [
            0x1C1C1E, 0xC4262E, 0x1A7F37, 0x8A6100, 0x0B5CC4, 0x8E36B8, 0x0C7A86, 0x6E6E73,
            0x48484A, 0xD93F46, 0x228B45, 0x9A6E00, 0x2F6FD6, 0xA04BC7, 0x138A97, 0x58585C,
        ].map(RGB.init)
    )
}
