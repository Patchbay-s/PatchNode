import Foundation

/// The termproxy wire format, as Proxmox's own xterm.js client speaks it
/// (pve-xtermjs): after the websocket opens, `user:ticket\n`; the server
/// answers `OK`, then raw terminal output. From the client:
/// `0:<byte count>:<data>` for input, `1:<cols>:<rows>:` for a resize, `2` as a
/// keep-alive every 30 s.
public enum TermProxyProtocol {
    public static let keepAliveInterval: Duration = .seconds(30)

    public static func handshake(user: String, ticket: String) -> Data {
        Data("\(user):\(ticket)\n".utf8)
    }

    public static func isAccepted(_ firstMessage: Data) -> Bool {
        firstMessage.starts(with: Array("OK".utf8))
    }

    /// The bytes after `OK` in the first message (some servers send output
    /// right after it).
    public static func outputAfterAcceptance(_ firstMessage: Data) -> Data {
        firstMessage.dropFirst(2)
    }

    /// The length is in bytes (UTF-8), not characters.
    public static func input(_ bytes: [UInt8]) -> Data {
        var data = Data("0:\(bytes.count):".utf8)
        data.append(contentsOf: bytes)
        return data
    }

    public static func resize(columns: Int, rows: Int) -> Data {
        Data("1:\(columns):\(rows):".utf8)
    }

    public static let keepAlive = Data("2".utf8)
}
