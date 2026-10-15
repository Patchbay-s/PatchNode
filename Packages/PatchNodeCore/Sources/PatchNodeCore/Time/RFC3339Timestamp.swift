import Foundation

/// RFC 3339 timestamps as Docker, Alertmanager and Grafana write them, with up to
/// nanosecond precision ("2024-05-01T10:00:00.123456789Z", "…+02:00"), which
/// ISO8601DateFormatter doesn't reliably accept. Invalid or impossible dates → nil.
public enum RFC3339Timestamp {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func parse(_ text: String) -> Date? {
        parse(Substring(text))
    }

    public static func parse(_ text: Substring) -> Date? {
        let bytes = Array(text.utf8)
        // YYYY-MM-DDTHH:MM:SS = 19 characters minimum, plus a zone.
        guard bytes.count >= 20,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              bytes[10] == UInt8(ascii: "T") || bytes[10] == UInt8(ascii: "t"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":"),
              let year = number(bytes, 0, 4), let month = number(bytes, 5, 2), let day = number(bytes, 8, 2),
              let hour = number(bytes, 11, 2), let minute = number(bytes, 14, 2), let second = number(bytes, 17, 2)
        else { return nil }

        var index = 19
        var fraction = 0.0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            let start = index
            while index < bytes.count, let digit = digit(bytes[index]) {
                fraction += Double(digit) * scale
                scale /= 10
                index += 1
            }
            guard index > start else { return nil }
        }

        var offset = 0
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "Z"), UInt8(ascii: "z"):
            index += 1
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            guard index + 6 <= bytes.count, bytes[index + 3] == UInt8(ascii: ":"),
                  let hours = number(bytes, index + 1, 2), let minutes = number(bytes, index + 4, 2)
            else { return nil }
            offset = (hours * 3600 + minutes * 60) * (bytes[index] == UInt8(ascii: "-") ? -1 : 1)
            index += 6
        default:
            return nil
        }
        guard index == bytes.count else { return nil }

        // Calendar would roll 2024-13-01 or 25:00 over instead of rejecting them.
        guard (1...12).contains(month), (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = utcCalendar.date(from: components),
              utcCalendar.component(.day, from: date) == day
        else { return nil }
        return date.addingTimeInterval(fraction - Double(offset))
    }

    private static func digit(_ byte: UInt8) -> Int? {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") ? Int(byte - UInt8(ascii: "0")) : nil
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ length: Int) -> Int? {
        guard start + length <= bytes.count else { return nil }
        var value = 0
        for index in start..<(start + length) {
            guard let digit = digit(bytes[index]) else { return nil }
            value = value * 10 + digit
        }
        return value
    }
}
