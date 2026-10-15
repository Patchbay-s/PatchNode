import Foundation
import PatchNodeCore
import SecurityKit

typealias SecurityStore = ServiceStore<SecurityServiceSnapshot, SecurityInventory>

extension ServiceStore where Snapshot == SecurityServiceSnapshot, Inventory == SecurityInventory {
    /// The Nginx Proxy Manager session token lives in `tokenCache` (memory only)
    /// until it expires, and is dropped as soon as the app goes to the background.
    static func security(secretStore: any SecretStore, tokenCache: AccessTokenCache = AccessTokenCache()) -> SecurityStore {
        SecurityStore(
            secretStore: secretStore,
            fetch: { service, credential, httpClient in
                try await SecurityProvider.loadSnapshot(
                    kind: service.kind, baseURL: service.url, credential: credential,
                    serviceID: service.id, serviceName: service.name,
                    tokenCache: tokenCache, httpClient: httpClient
                )
            },
            makeInventory: { SecurityInventory(snapshots: $0) },
            level: { inventory, failed, total in inventory.overview.level(failedServices: failed, totalServices: total) },
            onEnterBackground: { await tokenCache.removeAll() }
        )
    }

    func services(of kind: ServiceKind) -> [ServiceDescriptor] {
        services.filter { $0.kind == kind }
    }

    /// Traffic light for one kind of service (one dashboard card per kind).
    func level(of kind: ServiceKind) -> HealthLevel? {
        let matching = services(of: kind)
        guard !matching.isEmpty, hasLoadedOnce else { return nil }
        let ids = Set(matching.map(\.id))
        let failed = matching.count { states[$0.id]?.isFailure ?? false }
        let inventory = inventory
        let scoped = SecurityInventory.Scoped(inventory: inventory, serviceIDs: ids)
        if failed >= matching.count { return .critical }
        if failed > 0 { return .warning }
        switch kind {
        case .nginxProxyManager: return scoped.hosts.contains { $0.host.isFailing } ? .warning : .ok
        case .adGuardHome: return scoped.adGuards.contains { !$0.summary.protectionEnabled } ? .warning : .ok
        default: return .ok
        }
    }
}

extension SecurityInventory {
    /// The part of the inventory that belongs to some services.
    struct Scoped {
        let decisions: [DecisionItem]
        let hosts: [HostItem]
        let adGuards: [AdGuardItem]

        init(inventory: SecurityInventory, serviceIDs: Set<UUID>) {
            decisions = inventory.decisions.filter { serviceIDs.contains($0.serviceID) }
            hosts = inventory.hosts.filter { serviceIDs.contains($0.serviceID) }
            adGuards = inventory.adGuards.filter { serviceIDs.contains($0.serviceID) }
        }
    }
}
