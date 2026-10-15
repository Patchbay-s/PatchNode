import Foundation
import PatchNodeCore

extension ProxmoxInventory {
    /// "HomeLab node-b · pve": service first (two services may both have a "pve").
    static func sharedTitle(serviceName: String, node: String) -> String {
        serviceName.isEmpty || serviceName == node ? node : "\(serviceName) · \(node)"
    }

    /// Node load for the medium widget: online nodes first, then by title.
    public func sharedNodeLoads() -> [SharedSnapshot.NodeLoad] {
        nodes.compactMap { item -> SharedSnapshot.NodeLoad? in
            guard let node = item.resource.node else { return nil }
            return SharedSnapshot.NodeLoad(
                id: item.id,
                title: Self.sharedTitle(serviceName: item.serviceName, node: node),
                isOnline: item.resource.isOnline,
                // Rounded to the percent the widget shows: a 0.1 % change is no
                // reason to rewrite the file and reload the widgets.
                cpu: item.resource.isOnline ? item.resource.cpu.map(Self.percent) : nil,
                memory: item.resource.isOnline ? item.resource.memoryUsage.map(Self.percent) : nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func percent(_ fraction: Double) -> Double {
        (min(max(fraction, 0), 1) * 100).rounded() / 100
    }

    /// VMs and containers an App Intent may restart, by name.
    public func sharedGuestTargets() -> [SharedSnapshot.GuestTarget] {
        guests.compactMap { item -> SharedSnapshot.GuestTarget? in
            guard let target = ProxmoxActionTarget(item: item) else { return nil }
            return SharedSnapshot.GuestTarget(
                id: target.key,
                serviceID: target.serviceID,
                serviceName: item.serviceName,
                node: target.node,
                type: target.type.rawValue,
                vmid: target.vmid,
                name: item.resource.displayName
            )
        }
    }
}

extension ProxmoxActionTarget {
    /// The target an App Intent picked from the shared snapshot.
    public init?(shared: SharedSnapshot.GuestTarget) {
        guard let type = ProxmoxGuestType(rawValue: shared.type) else { return nil }
        self.init(serviceID: shared.serviceID, node: shared.node, type: type, vmid: shared.vmid)
    }
}
