import Foundation
import PatchNodeCore

/// Why a Proxmox console couldn't open or dropped. Codes only: the app shows
/// the text, Diagnostics the code.
public enum ConsoleFailure: Error, Sendable, Equatable, TerminalFailure {
    /// 403: the token lacks VM.Console / Sys.Console.
    case missingPrivilege
    /// 401 on the websocket: Proxmox VE older than 9.1 refuses API tokens for
    /// consoles (or the token was revoked).
    case tokenRefused
    /// Network, VPN, reverse proxy without websockets.
    case unreachable
    /// termproxy didn't answer `OK` (expired ticket).
    case handshakeFailed
    /// A VM without a serial port was asked for a terminal.
    case noSerialPort
    /// Anything else the API answered.
    case server(Int)

    public var code: String {
        switch self {
        case .missingPrivilege: "pve-forbidden"
        case .tokenRefused: "pve-token-refused"
        case .unreachable: "pve-unreachable"
        case .handshakeFailed: "pve-handshake"
        case .noSerialPort: "pve-no-serial"
        case .server(let status): "pve-http-\(status)"
        }
    }

    init(_ error: any Error) {
        switch error {
        case let failure as ConsoleFailure: self = failure
        case ServiceProviderError.forbidden: self = .missingPrivilege
        case ServiceProviderError.unauthorized: self = .tokenRefused
        case ServiceProviderError.unexpectedStatus(let status): self = .server(status)
        default: self = .unreachable
        }
    }

    static func fromUpgradeStatus(_ status: Int?) -> ConsoleFailure {
        switch status {
        case 401: .tokenRefused
        case 403: .missingPrivilege
        case let status?: .server(status)
        case nil: .unreachable
        }
    }
}
