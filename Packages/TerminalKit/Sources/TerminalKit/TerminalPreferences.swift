import Foundation

/// Per-device terminal settings (not synced, not secret).
public enum TerminalPreferences {
    public static let fontSizeKey = "terminal.fontSize"
    public static let fontSizes: ClosedRange<Double> = 9...28
    public static let defaultFontSize: Double = 13

    public static func fontSize(_ defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: fontSizeKey)
        return stored == 0 ? defaultFontSize : clamped(stored)
    }

    public static func setFontSize(_ size: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(clamped(size), forKey: fontSizeKey)
    }

    public static func clamped(_ size: Double) -> Double {
        min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
    }
}
