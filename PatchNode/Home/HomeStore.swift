import Foundation
import PatchNodeCore
import HomeServicesKit

typealias HomeStore = ServiceStore<HomeServiceSnapshot, HomeServicesInventory>

extension ServiceStore where Snapshot == HomeServiceSnapshot, Inventory == HomeServicesInventory {
    static func home(secretStore: any SecretStore) -> HomeStore {
        HomeStore(
            secretStore: secretStore,
            fetch: { service, credential, httpClient in
                try await HomeServicesProvider.loadSnapshot(
                    kind: service.kind, baseURL: service.url, credential: credential,
                    serviceID: service.id, serviceName: service.name, httpClient: httpClient
                )
            },
            makeInventory: { HomeServicesInventory(snapshots: $0) },
            // Per-kind levels are computed by `level(of:)`.
            level: { _, failed, total in
                if total > 0 && failed >= total { return .critical }
                return failed > 0 ? .warning : .ok
            }
        )
    }

    func services(of kind: ServiceKind) -> [ServiceDescriptor] {
        services.filter { $0.kind == kind }
    }

    /// Traffic light for one kind of service (one dashboard card per kind).
    func level(of kind: ServiceKind) -> HealthLevel? {
        let matching = services(of: kind)
        guard !matching.isEmpty, hasLoadedOnce else { return nil }
        let failed = matching.count { states[$0.id]?.isFailure ?? false }
        return inventory.level(kind: kind, failedServices: failed, totalServices: matching.count)
    }

    /// Client for triggering a scene or script; nil while the token is refused.
    func homeAssistantClient(for serviceID: UUID) async -> HomeAssistantClient? {
        guard let (service, token) = await credentials(for: serviceID), service.kind == .homeAssistant else { return nil }
        return HomeAssistantClient(baseURL: service.url, token: token, httpClient: httpClient(for: service))
    }
}
