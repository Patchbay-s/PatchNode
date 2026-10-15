import Foundation

/// What an SSH host is attached to, for the shortcuts (a Proxmox node's
/// "Enter the CT", a Docker host's compose projects).
public enum SSHHostLink: String, Sendable, Hashable, CaseIterable, Codable {
    case none = ""
    /// A Proxmox VE service's node (`linkedTarget` = node name).
    case proxmoxNode
    /// A container or VM (`linkedTarget` = VMID) of a Proxmox VE service.
    case proxmoxGuest
    /// A Docker host (`linkedTarget` = host id from DockerKit).
    case dockerHost
}

#if canImport(SwiftData)
import SwiftData

/// A server reachable over SSH (schema V3, 1.2). No secret: the device's key
/// stays in the Keychain, a password is typed at each connection. Synced
/// through iCloud with the rest of the configuration when sync is on.
@Model
public final class SSHHost {
    public var id: UUID = UUID()
    public var name: String = ""
    public var hostname: String = ""
    public var port: Int = 22
    public var username: String = ""
    public var linkRawValue: String = ""
    public var linkedServiceID: UUID? = nil
    public var linkedTarget: String = ""
    /// `SHA256:…` of the host key accepted at the first connection; empty
    /// until then. A different key is refused.
    public var pinnedHostKey: String = ""
    public var createdAt: Date = Date.distantPast

    public var link: SSHHostLink {
        get { SSHHostLink(rawValue: linkRawValue) ?? .none }
        set { linkRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(), name: String, hostname: String, port: Int = 22, username: String,
        link: SSHHostLink = .none, linkedServiceID: UUID? = nil, linkedTarget: String = "",
        pinnedHostKey: String = "", createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.linkRawValue = link.rawValue
        self.linkedServiceID = linkedServiceID
        self.linkedTarget = linkedTarget
        self.pinnedHostKey = pinnedHostKey
        self.createdAt = createdAt
    }
}
#endif
