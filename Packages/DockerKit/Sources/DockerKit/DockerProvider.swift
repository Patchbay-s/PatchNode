import Foundation
import PatchNodeCore

public enum DockerProviderError: Error, Sendable, Equatable {
    case unreachable
}

/// Portainer or a direct Docker Engine (socket proxy), same models for both.
public struct DockerProvider: ServiceProvider {
    public let id: UUID
    public let kind: ServiceKind
    public let displayName: String
    public let client: DockerClient

    /// `credential`: Portainer access token, or `user:password` for the reverse
    /// proxy in front of the socket proxy.
    public init(id: UUID, kind: ServiceKind, displayName: String, baseURL: URL, credential: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.client = DockerClient(
            flavor: kind == .dockerPortainer ? .portainer : .engine,
            baseURL: baseURL,
            credential: credential,
            httpClient: httpClient,
            engineName: displayName
        )
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            try await client.checkConnection()
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
            return .unreachable(DockerProviderError.unreachable)
        }
    }

    /// Running / stopped / unhealthy containers across every host.
    public func summary() async throws -> ServiceSummary {
        let snapshot = try await Self.loadSnapshot(client: client, serviceID: id, serviceName: displayName)
        let overview = DockerInventory(snapshots: [snapshot]).overview
        return ServiceSummary(
            headline: "\(overview.running)/\(overview.total)",
            details: [
                "running": String(overview.running),
                "stopped": String(overview.stopped),
                "unhealthy": String(overview.unhealthy),
                "total": String(overview.total),
            ]
        )
    }

    /// Environments queried at once when Portainer manages several hosts.
    static let maxConcurrentHosts = 4

    /// Hosts, then each host's containers in parallel (a host failing doesn't fail
    /// the others, except a refused key), with Portainer stacks alongside (optional).
    public static func loadSnapshot(client: DockerClient, serviceID: UUID, serviceName: String) async throws -> DockerServiceSnapshot {
        let hosts = try await client.hosts()
        async let stacks = (try? await client.stacks()) ?? []

        let hostSnapshots = try await withThrowingTaskGroup(of: (Int, DockerHostSnapshot).self) { group in
            var results: [(Int, DockerHostSnapshot)] = []
            var next = 0

            func addNext() {
                guard next < hosts.count else { return }
                let index = next
                let host = hosts[index]
                next += 1
                group.addTask {
                    guard host.status != .down else {
                        return (index, DockerHostSnapshot(host: host, containers: [], error: .unreachable))
                    }
                    do {
                        return (index, DockerHostSnapshot(host: host, containers: try await client.containers(on: host)))
                    } catch let error as ServiceProviderError {
                        // A refused key fails the whole service (no point asking other hosts).
                        if error == .unauthorized { throw error }
                        return (index, DockerHostSnapshot(host: host, containers: [], error: error))
                    }
                }
            }

            for _ in 0..<maxConcurrentHosts { addNext() }
            while let result = try await group.next() {
                results.append(result)
                addNext()
            }
            // Keep Portainer's environment order.
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        // A 403 on the only engine, or on every Portainer environment, means the
        // credential can read nothing: fail the service so it gets paused instead of
        // repeating refused requests every cycle (CrowdSec / fail2ban).
        // Same for a reverse proxy refusing every host (VPN off, Access List, ban).
        let refused = hostSnapshots.filter { $0.error == .forbidden || $0.error == .blockedByProxy }
        if !refused.isEmpty && (client.flavor == .engine || refused.count == hostSnapshots.count) {
            throw refused.contains { $0.error == .forbidden } ? ServiceProviderError.forbidden : ServiceProviderError.blockedByProxy
        }
        return DockerServiceSnapshot(serviceID: serviceID, serviceName: serviceName, hosts: hostSnapshots, stacks: await stacks)
    }
}
