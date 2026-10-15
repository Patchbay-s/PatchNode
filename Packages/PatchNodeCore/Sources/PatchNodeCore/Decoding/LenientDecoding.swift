import Foundation

/// Homelab APIs (Proxmox, Docker…) send fields that are sometimes missing, sometimes
/// numbers, sometimes strings ("0.25", "1"), and occasionally null. These helpers
/// never throw: an unusable value simply decodes as nil.
extension KeyedDecodingContainer {
    public func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }
        if let string = try? decodeIfPresent(String.self, forKey: key),
           let value = Double(string.trimmingCharacters(in: .whitespaces)), value.isFinite {
            return value
        }
        if let bool = try? decodeIfPresent(Bool.self, forKey: key) {
            return bool ? 1 : 0
        }
        return nil
    }

    public func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        // Int(exactly:) instead of a range check: Double(Int.max) rounds up to 2^63,
        // so a bound check would still let Int(_:) trap on an absurd server value.
        guard let double = lenientDouble(key) else { return nil }
        return Int(exactly: double.rounded(.towardZero))
    }

    public func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    /// Booleans arrive as 0/1, "0"/"1" or true/false.
    public func lenientBool(_ key: Key) -> Bool? {
        // Numbers first: Proxmox almost always sends 0/1.
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = lenientDouble(key) { return value != 0 }
        return nil
    }
}

/// Decodes an array element by element, dropping elements that fail instead of
/// failing the whole list (one malformed VM must not hide all the others).
public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(DiscardedValue.self)
            }
        }
        self.elements = elements
    }

    private struct DiscardedValue: Decodable {}
}

public struct AnyCodingKey: CodingKey {
    public let stringValue: String
    public let intValue: Int? = nil
    public init(_ string: String) { stringValue = string }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
}
