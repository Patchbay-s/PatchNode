import Foundation
import PatchNodeCore

/// Why an SSH connection failed. Codes only (no host, no server text): the
/// app shows the words, Diagnostics the code.
public enum SSHFailure: Error, Sendable, Equatable, TerminalFailure {
    case unreachable
    /// First contact: the host key must be shown and accepted first.
    case hostKeyUnknown(fingerprint: String, algorithm: String)
    /// The host presented another key than the pinned one: refused.
    case hostKeyChanged(presented: String)
    /// Neither the key nor (if given) the password was accepted.
    case authenticationFailed(passwordAllowed: Bool)
    /// The user dismissed the password prompt.
    case cancelled
    /// The server refused the shell or the command.
    case channelRefused
    case timedOut
    case closed

    public var code: String {
        switch self {
        case .unreachable: "ssh-unreachable"
        case .hostKeyUnknown: "ssh-host-key-unknown"
        case .hostKeyChanged: "ssh-host-key-changed"
        case .authenticationFailed: "ssh-auth-failed"
        case .cancelled: "ssh-cancelled"
        case .channelRefused: "ssh-channel-refused"
        case .timedOut: "ssh-timeout"
        case .closed: "ssh-closed"
        }
    }
}
