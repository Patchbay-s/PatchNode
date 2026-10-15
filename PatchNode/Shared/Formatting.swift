import Foundation

/// Display formatting shared by the Proxmox screens.
enum Format {
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "–" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func bytes(_ value: Int?) -> String {
        guard let value else { return "–" }
        return Int64(value).formatted(.byteCount(style: .memory))
    }

    static func bytes(_ value: Double) -> String {
        guard let bytes = int64(value) else { return "–" }
        return bytes.formatted(.byteCount(style: .memory))
    }

    /// Throughput from rrddata (bytes per second).
    static func rate(_ bytesPerSecond: Double) -> String {
        guard let rate = int64(bytesPerSecond) else { return "–" }
        let amount = rate.formatted(.byteCount(style: .decimal))
        return String(localized: "\(amount)/s")
    }

    static func usage(_ used: Int?, of total: Int?) -> String {
        String(localized: "\(bytes(used)) of \(bytes(total))")
    }

    static func uptime(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, let seconds = int64(interval) else { return "–" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)
        )
    }
}

extension Format {
    /// Whole count (vCPUs) from a server value that may be absurd.
    static func count(_ value: Double) -> String {
        guard let count = int64(value) else { return "–" }
        return String(count)
    }

    /// Server values are untrusted: a huge or non-finite number must not crash
    /// the Int64 conversion.
    static func int64(_ value: Double) -> Int64? {
        guard value.isFinite else { return nil }
        return Int64(exactly: value.rounded())
    }
}

/// Refresh interval chosen in Réglages (non-secret, stored in UserDefaults).
enum RefreshSettings {
    static let key = "refreshIntervalSeconds"
    static let defaultInterval = 60
    static let options = [30, 60, 120, 300]
}
