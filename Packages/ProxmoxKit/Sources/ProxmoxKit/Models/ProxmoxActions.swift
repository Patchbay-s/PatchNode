import Foundation
import PatchNodeCore

/// Power actions on a VM or container (`POST …/status/{action}`, needs VM.PowerMgmt, e.g. a PatchNodePower role).
public enum ProxmoxGuestAction: String, Sendable, Hashable, CaseIterable {
    case start
    /// Clean ACPI shutdown (guest agent / ACPI).
    case shutdown
    /// Forced stop, like pulling the plug.
    case stop
    case reboot

    public var isForced: Bool { self == .stop }
}

/// `GET /nodes/{node}/tasks/{upid}/status`.
public struct ProxmoxTaskStatus: Sendable, Hashable, Decodable {
    public let isRunning: Bool
    /// "OK", "WARNINGS: n", or an error message once finished.
    public let exitStatus: String?

    public init(isRunning: Bool, exitStatus: String?) {
        self.isRunning = isRunning
        self.exitStatus = exitStatus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        isRunning = c.lenientString(AnyCodingKey("status")) == "running"
        let exit = c.lenientString(AnyCodingKey("exitstatus"))
        exitStatus = (exit?.isEmpty ?? true) ? nil : exit
    }

    public var succeeded: Bool {
        guard !isRunning, let exitStatus else { return false }
        return exitStatus == "OK" || exitStatus.hasPrefix("WARNINGS")
    }
}

public enum ProxmoxActionError: Error, Sendable, Hashable {
    /// The task didn't finish before the global timeout (it may still complete).
    case taskTimedOut(upid: String)
    /// The server didn't return a task id.
    case missingTaskID
}
