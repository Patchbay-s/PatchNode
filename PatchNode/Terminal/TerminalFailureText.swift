import Foundation
import PatchNodeCore
import RemoteAccessKit

/// The text shown when a session couldn't open or dropped. Packages only give
/// codes; the words are here, in the five languages.
enum TerminalFailureText {
    static func message(for error: any Error) -> String {
        switch error {
        case let failure as ConsoleFailure:
            switch failure {
            case .missingPrivilege:
                String(localized: "The token lacks the console privilege (VM.Console, or Sys.Console for a node).")
            case .tokenRefused:
                String(localized: "Proxmox refused the token for the console. Consoles with an API token need Proxmox VE 9.1 or later.")
            case .unreachable:
                String(localized: "The console couldn't be reached. Check the VPN, and that the reverse proxy allows websockets.")
            case .handshakeFailed:
                String(localized: "Proxmox refused the console ticket. Try again.")
            case .noSerialPort:
                String(localized: "This VM has no serial port: use its graphical console.")
            case .server(let status):
                String(localized: "Proxmox answered with an error (HTTP \(status)).")
            }
        case is VNCAuthenticationFailure:
            String(localized: "The graphical console refused the connection. Try again.")
        case is VNCPageFailure:
            String(localized: "The graphical console stopped. Reconnect to open it again.")
        default:
            sshMessage(for: error) ?? String(localized: "Connection lost.")
        }
    }

    static func sshMessage(for error: any Error) -> String? {
        guard let failure = error as? SSHFailure else { return nil }
        return switch failure {
        case .unreachable:
            String(localized: "The SSH server couldn't be reached. Check the VPN, the address and the port.")
        case .hostKeyUnknown:
            String(localized: "This host's key hasn't been checked yet: connect from Settings › SSH to see its fingerprint.")
        case .hostKeyChanged(let presented):
            String(localized: "The server presented another host key (\(presented)). The connection was refused: it may be an impersonation. If you reinstalled the server, check the new fingerprint, then forget the old key in Settings › SSH.")
        case .authenticationFailed(let passwordAllowed):
            passwordAllowed
                ? String(localized: "The server refused this device's key and the password.")
                : String(localized: "The server refused this device's key. Add the authorized_keys line from Settings › SSH to the user's ~/.ssh/authorized_keys.")
        case .cancelled:
            String(localized: "Connection cancelled.")
        case .channelRefused:
            String(localized: "The server refused to open a shell or run the command.")
        case .timedOut:
            String(localized: "The SSH server didn't answer in time.")
        case .closed:
            String(localized: "The SSH connection was closed.")
        }
    }
}
