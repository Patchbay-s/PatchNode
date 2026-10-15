import Foundation

public struct DockerLogLine: Sendable, Hashable, Identifiable {
    public enum Stream: Sendable, Hashable {
        case stdout
        case stderr
        /// TTY containers: stdout and stderr arrive merged, not multiplexed.
        case console
    }

    /// Position in the decoded output (stable for a given response).
    public let id: Int
    public let stream: Stream
    public let timestamp: Date?
    public let text: String
}

/// Decodes `GET /containers/{id}/logs`.
///
/// Without a TTY, Docker multiplexes stdout and stderr: each frame starts with an
/// 8-byte header — stream (1 = stdout, 2 = stderr), three zero bytes, payload size
/// as a big-endian UInt32. With a TTY the body is the raw console output. The mode
/// is detected from the first header; a frame (or a line) may be split across
/// `append` calls. Lines are cleaned of ANSI escape sequences and control
/// characters, and the `timestamps=true` prefix is parsed when requested.
public struct DockerLogDecoder: Sendable {
    private enum Mode: Sendable { case undetermined, multiplexed, raw }

    private let parsesTimestamps: Bool
    private var mode: Mode = .undetermined
    private var buffer: [UInt8] = []
    private var readIndex = 0
    private var pendingLine: [DockerLogLine.Stream: [UInt8]] = [:]
    private var nextID = 0

    public init(timestamps: Bool) {
        parsesTimestamps = timestamps
    }

    /// Decodes a complete response body.
    public static func decode(_ data: Data, timestamps: Bool) -> [DockerLogLine] {
        var decoder = DockerLogDecoder(timestamps: timestamps)
        return decoder.append(data) + decoder.finish()
    }

    /// Feeds more bytes; returns the lines completed so far.
    public mutating func append(_ data: Data) -> [DockerLogLine] {
        buffer.append(contentsOf: data)
        return drain(final: false)
    }

    /// Flushes whatever is left (a last line without newline, a truncated frame).
    public mutating func finish() -> [DockerLogLine] {
        var lines = drain(final: true)
        for stream in [DockerLogLine.Stream.stdout, .stderr, .console] {
            if let rest = pendingLine.removeValue(forKey: stream), !rest.isEmpty {
                lines.append(contentsOf: makeLine(rest, stream: stream))
            }
        }
        return lines
    }

    // MARK: - Framing

    private mutating func drain(final: Bool) -> [DockerLogLine] {
        var lines: [DockerLogLine] = []

        if mode == .undetermined {
            let available = buffer.count - readIndex
            if available >= 8 {
                mode = Self.looksLikeHeader(buffer, at: readIndex) ? .multiplexed : .raw
            } else if final {
                mode = .raw
            } else {
                return lines
            }
        }

        if mode == .multiplexed {
            while buffer.count - readIndex >= 8 {
                guard Self.looksLikeHeader(buffer, at: readIndex) else {
                    // Corrupt or unexpected framing: show the rest as raw text rather
                    // than dropping it.
                    mode = .raw
                    break
                }
                let size = Int(buffer[readIndex + 4]) << 24 | Int(buffer[readIndex + 5]) << 16
                    | Int(buffer[readIndex + 6]) << 8 | Int(buffer[readIndex + 7])
                let stream: DockerLogLine.Stream = buffer[readIndex] == 2 ? .stderr : .stdout
                let payloadStart = readIndex + 8
                let available = buffer.count - payloadStart
                if available < size {
                    guard final else { break }
                    // Truncated last frame: keep what arrived.
                    lines.append(contentsOf: consume(Array(buffer[payloadStart...]), stream: stream))
                    readIndex = buffer.count
                    break
                }
                lines.append(contentsOf: consume(Array(buffer[payloadStart..<(payloadStart + size)]), stream: stream))
                readIndex = payloadStart + size
            }
            if final, mode == .multiplexed, readIndex < buffer.count {
                // Fewer than 8 bytes left: not a frame, keep them as text.
                lines.append(contentsOf: consume(Array(buffer[readIndex...]), stream: .stdout))
                readIndex = buffer.count
            }
        }

        if mode == .raw, readIndex < buffer.count {
            lines.append(contentsOf: consume(Array(buffer[readIndex...]), stream: .console))
            readIndex = buffer.count
        }

        compact()
        return lines
    }

    private static func looksLikeHeader(_ bytes: [UInt8], at index: Int) -> Bool {
        bytes[index] <= 2 && bytes[index + 1] == 0 && bytes[index + 2] == 0 && bytes[index + 3] == 0
    }

    private mutating func compact() {
        if readIndex == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            readIndex = 0
        } else if readIndex > 64 * 1024 {
            buffer.removeFirst(readIndex)
            readIndex = 0
        }
    }

    // MARK: - Lines

    private mutating func consume(_ payload: [UInt8], stream: DockerLogLine.Stream) -> [DockerLogLine] {
        var pending = pendingLine.removeValue(forKey: stream) ?? []
        var lines: [DockerLogLine] = []
        var start = 0
        for index in payload.indices where payload[index] == UInt8(ascii: "\n") {
            pending.append(contentsOf: payload[start..<index])
            lines.append(contentsOf: makeLine(pending, stream: stream))
            pending.removeAll(keepingCapacity: true)
            start = index + 1
        }
        pending.append(contentsOf: payload[start...])
        if !pending.isEmpty { pendingLine[stream] = pending }
        return lines
    }

    /// Longer lines (base64 dumps…) are cut so one line can't freeze the UI.
    public static let maxLineBytes = 16 * 1024

    private mutating func makeLine(_ bytes: [UInt8], stream: DockerLogLine.Stream) -> [DockerLogLine] {
        let truncated = bytes.count > Self.maxLineBytes
        var text = Self.clean(String(decoding: truncated ? Array(bytes.prefix(Self.maxLineBytes)) : bytes, as: UTF8.self))
        if truncated { text += "…" }
        var timestamp: Date?
        if parsesTimestamps, let space = text.firstIndex(of: " "),
           let date = DockerTimestamp.parse(text[..<space]) {
            timestamp = date
            text = String(text[text.index(after: space)...])
        } else if parsesTimestamps, let date = DockerTimestamp.parse(text) {
            // Empty line: only the timestamp.
            timestamp = date
            text = ""
        }
        defer { nextID += 1 }
        return [DockerLogLine(id: nextID, stream: stream, timestamp: timestamp, text: text)]
    }

    /// Removes ANSI escape sequences (colors, cursor moves), carriage returns and
    /// other control characters that would show up as garbage.
    static func clean(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            switch scalar.value {
            case 0x1B:
                // ESC [ … final byte (CSI), ESC ( x charset, ESC ] … BEL or ESC \ (OSC),
                // or a two-byte ESC x.
                guard let next = scalars.next() else { break }
                if next == "[" {
                    while let byte = scalars.next(), !(0x40...0x7E).contains(byte.value) {}
                } else if "()*+#".unicodeScalars.contains(next) {
                    // Charset designation, e.g. ESC ( B from `tput sgr0`: 3 bytes.
                    _ = scalars.next()
                } else if next == "]" {
                    var previousWasEscape = false
                    while let byte = scalars.next() {
                        if byte.value == 0x07 || (previousWasEscape && byte == "\\") { break }
                        previousWasEscape = byte.value == 0x1B
                    }
                }
            case 0x09:
                result.append(scalar)
            case 0x00...0x1F, 0x7F, 0x80...0x9F:
                continue
            case 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF:
                // Zero-width and bidirectional overrides: could make a line lie about
                // its content (reversed text, fake timestamp).
                continue
            default:
                result.append(scalar)
            }
        }
        return String(result)
    }
}
