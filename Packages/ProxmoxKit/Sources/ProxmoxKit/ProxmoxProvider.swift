import Foundation
import PatchNodeCore

public enum ProxmoxProviderError: Error, Sendable, Equatable {
    case unreachable
}

public struct ProxmoxProvider: ServiceProvider {
    public let id: UUID
    public let kind: ServiceKind = .proxmoxVE
    public let displayName: String

    public let client: ProxmoxClient

    /// `HealthStatus.degraded` reason when the token sees nothing (no PVEAuditor
    /// on / for a privilege-separated token).
    public static let insufficientRightsReason = "proxmox-insufficient-rights"

    /// `apiTokenValue` is what follows `PVEAPIToken=`: `<user>@<realm>!<tokenid>=<secret>`.
    public init(id: UUID, displayName: String, baseURL: URL, apiTokenValue: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.id = id
        self.displayName = displayName
        self.client = ProxmoxClient(baseURL: baseURL, apiTokenValue: apiTokenValue, httpClient: httpClient)
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            // One request checks the token, the rights and the reachability: a token
            // with Privilege Separation and no permission is accepted but sees only
            // bare nodes; say so instead of saving an empty service.
            let resources = try await client.clusterResources()
            if ProxmoxInventory.lacksPrivileges(resources) {
                return .degraded(Self.insufficientRightsReason)
            }
            return .ok
        } catch ServiceProviderError.blockedByProxy {
            // The reverse proxy refused (VPN off?): not a token problem.
            return .unreachable(ServiceProviderError.blockedByProxy)
        } catch ServiceProviderError.unauthorized, ServiceProviderError.forbidden {
            return .unauthorized
        } catch ServiceProviderError.unexpectedStatus(let code) {
            return .degraded("HTTP \(code)")
        } catch ServiceProviderError.invalidResponse, ServiceProviderError.decodingFailed {
            return .degraded("invalid response")
        } catch let error as CancellationError {
            throw error
        } catch {
            return .unreachable(ProxmoxProviderError.unreachable)
        }
    }

    /// Nodes online, running/total VMs and containers, storage above 85 %.
    public func summary() async throws -> ServiceSummary {
        let resources = try await client.clusterResources()
        let overview = ProxmoxInventory(
            snapshots: [ProxmoxServiceSnapshot(serviceID: id, serviceName: displayName, resources: resources)]
        ).overview
        return ServiceSummary(
            headline: "\(overview.nodesOnline)/\(overview.nodesTotal)",
            details: [
                "nodesOnline": String(overview.nodesOnline),
                "nodesTotal": String(overview.nodesTotal),
                "vmsRunning": String(overview.vmsRunning),
                "vmsTotal": String(overview.vmsTotal),
                "containersRunning": String(overview.containersRunning),
                "containersTotal": String(overview.containersTotal),
                "storagesAboveThreshold": String(overview.storagesAboveThreshold.count),
            ]
        )
    }
}
