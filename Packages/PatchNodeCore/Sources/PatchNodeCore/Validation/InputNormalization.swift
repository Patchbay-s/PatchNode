import Foundation

/// Cleans what the user typed or pasted into the URL and credential fields
/// before the connection test and the Keychain: spaces, line breaks and
/// invisible characters (zero-width space, BOM…) at either end, as a copy from a
/// web page or a password manager often adds.
public enum InputNormalization {
    private static let invisible = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")
    private static let trimmed = CharacterSet.whitespacesAndNewlines.union(invisible)

    public static func credential(_ raw: String) -> String {
        raw.trimmingCharacters(in: trimmed)
    }

    public static func url(_ raw: String) -> String {
        raw.trimmingCharacters(in: trimmed)
    }
}
