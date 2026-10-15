import Foundation
import PatchNodeCore

/// Docker timestamps are RFC 3339 with nanoseconds; parsing is shared in PatchNodeCore.
enum DockerTimestamp {
    static func parse(_ text: String) -> Date? {
        RFC3339Timestamp.parse(text)
    }

    static func parse(_ text: Substring) -> Date? {
        RFC3339Timestamp.parse(text)
    }
}
