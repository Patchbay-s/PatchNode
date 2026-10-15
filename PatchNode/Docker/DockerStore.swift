import Foundation
import PatchNodeCore
import DockerKit
import ProxmoxKit

typealias DockerStore = ServiceStore<DockerServiceSnapshot, DockerInventory>

extension ServiceStore where Snapshot == DockerServiceSnapshot, Inventory == DockerInventory {
    static func docker(secretStore: any SecretStore) -> DockerStore {
        DockerStore(
            secretStore: secretStore,
            // Portainer: one request per environment, 4 at a time.
            perServiceTimeout: 30,
            fetch: { service, token, httpClient in
                try await DockerProvider.loadSnapshot(
                    client: DockerClient(flavor: service.kind.dockerFlavor, baseURL: service.url, credential: token, httpClient: httpClient, engineName: service.name),
                    serviceID: service.id,
                    serviceName: service.name
                )
            },
            makeInventory: { DockerInventory(snapshots: $0) },
            level: { inventory, failed, total in inventory.overview.level(failedServices: failed, totalServices: total) }
        )
    }

    /// Client for one service (container detail screen); nil while its token is refused.
    func client(for serviceID: UUID) async -> DockerClient? {
        guard let (service, token) = await credentials(for: serviceID) else { return nil }
        return DockerClient(flavor: service.kind.dockerFlavor, baseURL: service.url, credential: token, httpClient: httpClient(for: service), engineName: service.name)
    }
}

extension ServiceKind {
    nonisolated var dockerFlavor: DockerAPIFlavor {
        self == .dockerPortainer ? .portainer : .engine
    }

    nonisolated var isDocker: Bool {
        self == .dockerPortainer || self == .dockerSocketProxy
    }
}
