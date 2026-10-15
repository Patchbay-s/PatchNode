import Foundation
import PatchNodeCore
import ProxmoxKit
import DockerKit

typealias ProxmoxStore = ServiceStore<ProxmoxServiceSnapshot, ProxmoxInventory>

extension ServiceStore where Snapshot == ProxmoxServiceSnapshot, Inventory == ProxmoxInventory {
    static func proxmox(secretStore: any SecretStore) -> ProxmoxStore {
        ProxmoxStore(
            secretStore: secretStore,
            // Resources, then tasks within their own 6 s: room for one retry of each.
            perServiceTimeout: 30,
            fetch: { service, token, httpClient in
                // Only /cluster/resources decides the service's state; the task
                // list is secondary (see ProxmoxServiceSnapshot.load).
                let client = ProxmoxClient(baseURL: service.url, apiTokenValue: token, httpClient: httpClient)
                // Never the disks: only `DiskHealthAccess` reads them.
                return try await ProxmoxServiceSnapshot.load(serviceID: service.id, serviceName: service.name, client: client)
            },
            makeInventory: { ProxmoxInventory(snapshots: $0) },
            level: { inventory, failed, total in inventory.overview.level(failedServices: failed, totalServices: total) },
            // A guest gone while its node answers may be hidden by an ACL, not
            // deleted: Diagnostics says so, nothing else claims a deletion.
            compare: { previous, current in
                let vmids = current.guestsNoLongerListed(since: previous)
                return vmids.isEmpty ? nil : .guestsNoLongerListed(vmids: vmids)
            }
        )
    }

    /// Client for one read that may run in the background (automatic SMART).
    func singleReadClient(for serviceID: UUID) async -> ProxmoxClient? {
        guard let (service, token) = await credentialsForSingleRead(for: serviceID) else { return nil }
        return ProxmoxClient(baseURL: service.url, apiTokenValue: token, httpClient: httpClient(for: service))
    }

    /// Client for one service (guest detail screen); nil while its token is refused.
    func client(for serviceID: UUID) async -> ProxmoxClient? {
        guard let (service, token) = await credentials(for: serviceID) else { return nil }
        return ProxmoxClient(baseURL: service.url, apiTokenValue: token, httpClient: httpClient(for: service))
    }
}
