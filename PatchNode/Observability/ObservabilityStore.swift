import Foundation
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit

typealias ObservabilityStore = ServiceStore<ObservabilityServiceSnapshot, ObservabilityInventory>

extension ServiceStore where Snapshot == ObservabilityServiceSnapshot, Inventory == ObservabilityInventory {
    static func observability(secretStore: any SecretStore) -> ObservabilityStore {
        ObservabilityStore(
            secretStore: secretStore,
            fetch: { service, token, httpClient in
                try await ObservabilityProvider.loadSnapshot(
                    kind: service.kind, baseURL: service.url, credential: token,
                    serviceID: service.id, serviceName: service.name, httpClient: httpClient
                )
            },
            makeInventory: { ObservabilityInventory(snapshots: $0) },
            level: { inventory, failed, total in inventory.overview.level(failedServices: failed, totalServices: total) }
        )
    }

    /// Prometheus services, for choosing where a PromQL favorite runs.
    var prometheusServices: [ServiceDescriptor] {
        services.filter { $0.kind == .prometheus }
    }

    /// Client for charting favorites; nil while the service's credential is refused.
    func prometheusClient(for serviceID: UUID) async -> PrometheusClient? {
        guard let (service, token) = await credentials(for: serviceID), service.kind == .prometheus else { return nil }
        // Queries can be heavy: a timed-out query_range is not sent a second time.
        return PrometheusClient(baseURL: service.url, credential: token, httpClient: httpClient(for: service, maxAttempts: 1))
    }
}
