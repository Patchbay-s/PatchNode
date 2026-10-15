import Foundation

/// An open terminal: an SSH shell, a Proxmox console (termproxy) or the demo.
/// Bytes only: the terminal view decodes them. Nothing here keeps or logs the
/// content of a session.
public protocol TerminalChannel: Sendable {
    /// What the remote side writes, until it closes (the stream finishes) or
    /// the connection fails (it throws).
    var output: AsyncThrowingStream<[UInt8], any Error> { get }
    /// What the user types, as is.
    func send(_ bytes: [UInt8]) async
    /// The terminal's size changed.
    func resize(_ size: TerminalSize) async
    /// Ends the session; `output` finishes.
    func close() async
}

/// Opens a channel; kept by a session so it can reconnect (manually only).
public protocol TerminalConnector: Sendable {
    /// Shown in the session's tab and in Diagnostics ("SSH", "Proxmox console").
    var kind: TerminalKind { get }
    func open(size: TerminalSize) async throws -> any TerminalChannel
}

public struct TerminalSize: Sendable, Hashable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        // A terminal is never smaller than this, whatever the view reports.
        self.columns = max(columns, 20)
        self.rows = max(rows, 5)
    }

    public static let standard = TerminalSize(columns: 80, rows: 24)
}

public enum TerminalKind: String, Sendable, Hashable, Codable {
    case ssh
    case proxmoxTerminal = "proxmox-terminal"
    case proxmoxGraphical = "proxmox-vnc"
    case demo
}

/// Why a session ended, without any of its content: shown on the closed
/// session and logged in Diagnostics.
public enum TerminalEndReason: Sendable, Hashable {
    /// The user closed it, or the remote shell exited.
    case closed
    /// The app stayed in the background longer than the grace period.
    case backgroundTimeout
    /// The connection failed or dropped; `code` is a short technical code
    /// (`TerminalFailure`), never a host or a message from the server.
    case failed(code: String)

    public var logValue: String {
        switch self {
        case .closed: "closed"
        case .backgroundTimeout: "background-timeout"
        case .failed(let code): "failed(\(code))"
        }
    }
}

/// An error a connector throws when a session can't open or drops: a short
/// technical code for Diagnostics (no host, no server message) and a
/// localized explanation for the screen.
public protocol TerminalFailure: Error {
    var code: String { get }
}
