import Foundation

/// Commands run over SSH on a Proxmox node.
public enum ProxmoxSSHCommands {
    /// `pct enter <vmid>`: a shell inside the container. Needs root: through
    /// sudo for any other user (see the SSH guide for the sudoers rule). The
    /// VMID is a number, never text from the server.
    public static func enterContainer(vmid: Int, user: String) -> String? {
        guard vmid > 0 else { return nil }
        return user == "root" ? "pct enter \(vmid)" : "sudo pct enter \(vmid)"
    }
}
