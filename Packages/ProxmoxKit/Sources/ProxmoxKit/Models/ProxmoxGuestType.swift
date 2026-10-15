public enum ProxmoxGuestType: String, Sendable, Hashable, CaseIterable, Codable {
    case qemu
    case lxc
}

public enum ProxmoxRRDTimeframe: String, Sendable, Hashable, CaseIterable {
    case hour
    case day
    case week
}
