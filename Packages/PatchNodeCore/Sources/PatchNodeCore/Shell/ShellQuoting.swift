import Foundation

/// The only way a value reaches a remote shell (SSH commands, compose paths,
/// project names, `pveum` lines shown to copy): POSIX single quotes, where
/// nothing is special except the quote itself, written `'\''`.
///
/// Control characters (NUL, line breaks, escape…) are refused outright rather
/// than quoted: a path or a name never needs them, and a line break could end
/// a command in a context we don't control (a `sudo` prompt, a here-doc).
public enum ShellQuoting {
    public enum Failure: Error, Sendable, Equatable {
        case controlCharacter
        case empty
    }

    /// `it's` → `'it'\''s'`.
    public static func quote(_ value: String) throws -> String {
        guard !value.isEmpty else { throw Failure.empty }
        guard !value.unicodeScalars.contains(where: isControl) else { throw Failure.controlCharacter }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A command and its arguments, each quoted, joined by spaces.
    public static func command(_ arguments: [String]) throws -> String {
        try arguments.map(quote).joined(separator: " ")
    }

    public static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
            // Bidirectional overrides: a name that reads differently than it runs.
            || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }
}
