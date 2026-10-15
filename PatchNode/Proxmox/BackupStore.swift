import Foundation
import PatchNodeCore
import ProxmoxKit

typealias BackupStore = ServiceStore<PBSServiceSnapshot, PBSInventory>

extension ServiceStore where Snapshot == PBSServiceSnapshot, Inventory == PBSInventory {
    static func backups(secretStore: any SecretStore) -> BackupStore {
        BackupStore(
            secretStore: secretStore,
            // Two requests per datastore, sequential.
            perServiceTimeout: 40,
            fetch: { service, token, httpClient in
                try await PBSProvider.loadSnapshot(
                    client: PBSClient(baseURL: service.url, apiTokenValue: token, httpClient: httpClient),
                    serviceID: service.id,
                    serviceName: service.name
                )
            },
            makeInventory: { PBSInventory(snapshots: $0) },
            level: { inventory, failed, total in inventory.overview.level(failedServices: failed, totalServices: total) }
        )
    }
}
