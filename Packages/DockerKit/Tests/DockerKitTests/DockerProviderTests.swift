import Foundation
import Testing
import PatchNodeCore
@testable import DockerKit

private typealias F = DockerFixtures
private let serviceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

private func portainerProvider(_ fake: FakeHTTPClient) -> DockerProvider {
    DockerProvider(id: serviceID, kind: .dockerPortainer, displayName: "Portainer",
                   baseURL: F.portainerURL, credential: F.portainerKey, httpClient: fake)
}

private func engineProvider(_ fake: FakeHTTPClient) -> DockerProvider {
    DockerProvider(id: serviceID, kind: .dockerSocketProxy, displayName: "Docker",
                   baseURL: F.engineURL, credential: F.engineCredential, httpClient: fake)
}

private let kinds: [ServiceKind] = [.dockerPortainer, .dockerSocketProxy]

private func provider(_ kind: ServiceKind, _ fake: FakeHTTPClient) -> DockerProvider {
    kind == .dockerPortainer ? portainerProvider(fake) : engineProvider(fake)
}

private let endpoint1Containers = """
[
  {"Id": "a1", "Names": ["/traefik"], "State": "running", "Status": "Up 3 hours (healthy)",
   "Labels": {"com.docker.compose.project": "proxy"}},
  {"Id": "a2", "Names": ["/test-container"], "State": "running", "Status": "Up 3 hours (unhealthy)",
   "Labels": {"com.docker.compose.project": "media"}},
  {"Id": "a3", "Names": ["/backup"], "State": "exited", "Status": "Exited (1) 2 hours ago"}
]
"""

private let endpoint2Containers = """
[
  {"Id": "b1", "Names": ["/pihole"], "State": "running", "Status": "Up 5 days"},
  {"Id": "b2", "Names": ["/certbot"], "State": "exited", "Status": "Exited (0) 12 hours ago"}
]
"""

private let twoEndpoints = F.endpointsJSON([(1, "local", 1), (2, "storage-node", 1)])

@Suite struct DockerProviderHealthTests {
    @Test func flavorFollowsKind() {
        #expect(portainerProvider(FakeHTTPClient(.timeout)).client.flavor == .portainer)
        #expect(engineProvider(FakeHTTPClient(.timeout)).client.flavor == .engine)
    }

    @Test(arguments: kinds)
    func healthCheckOK(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(F.endpoints),
            "/version": .json(#"{"Version":"26.1.4","ApiVersion":"1.45"}"#),
        ])
        let status = try await provider(kind, fake).healthCheck()
        guard case .ok = status else {
            Issue.record("Expected .ok, got \(status)")
            return
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: kinds)
    func healthCheckReturnsUnauthorizedOn401WithoutRetry(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(.unauthorized)
        let status = try await provider(kind, fake).healthCheck()
        guard case .unauthorized = status else {
            Issue.record("Expected .unauthorized, got \(status)")
            return
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: kinds)
    func healthCheckReturnsUnauthorizedOn403WithoutRetry(kind: ServiceKind) async throws {
        let fake = FakeHTTPClient(.forbidden)
        let status = try await provider(kind, fake).healthCheck()
        guard case .unauthorized = status else {
            Issue.record("Expected .unauthorized, got \(status)")
            return
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: kinds)
    func healthCheckIsDegradedOn500(kind: ServiceKind) async throws {
        let status = try await provider(kind, FakeHTTPClient(.serverError)).healthCheck()
        guard case let .degraded(message) = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
        #expect(message.contains("500"))
    }

    @Test func healthCheckIsDegradedOnInvalidJSON() async throws {
        let status = try await portainerProvider(FakeHTTPClient.json("<html>login</html>")).healthCheck()
        guard case .degraded = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
    }

    @Test(arguments: kinds)
    func healthCheckIsUnreachableOnTimeout(kind: ServiceKind) async throws {
        let status = try await provider(kind, FakeHTTPClient(.timeout)).healthCheck()
        guard case let .unreachable(error) = status else {
            Issue.record("Expected .unreachable, got \(status)")
            return
        }
        #expect(error as? DockerProviderError == .unreachable)
    }

    @Test(arguments: kinds)
    func healthCheckRethrowsCancellation(kind: ServiceKind) async {
        await #expect(throws: CancellationError.self) {
            _ = try await provider(kind, FakeHTTPClient(.failure(CancellationError()))).healthCheck()
        }
    }
}

@Suite struct DockerProviderSnapshotTests {
    @Test func summaryAggregatesTwoPortainerEndpoints() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .json(endpoint1Containers),
            "/api/endpoints/2/docker/containers/json": .json(endpoint2Containers),
            "/api/stacks": .json(F.stacks),
        ])
        let summary = try await portainerProvider(fake).summary()
        #expect(summary.headline == "3/5")
        #expect(summary.details == ["running": "3", "stopped": "2", "unhealthy": "1", "total": "5"])
    }

    @Test func engineSummary() async throws {
        let fake = FakeHTTPClient(routes: ["/containers/json": .json(endpoint1Containers)])
        let summary = try await engineProvider(fake).summary()
        #expect(summary.details == ["running": "2", "stopped": "1", "unhealthy": "1", "total": "3"])
        #expect(await fake.receivedPaths == ["/containers/json"])
    }

    @Test func summaryThrowsUnauthorizedOn401() async {
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await portainerProvider(FakeHTTPClient(.unauthorized)).summary()
        }
    }

    @Test func hostWithFailingContainersCallGetsErrorOthersStillLoad() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .serverError,
            "/api/endpoints/2/docker/containers/json": .json(endpoint2Containers),
            "/api/stacks": .json(F.stacks),
        ])
        let client = portainerProvider(fake).client
        let snapshot = try await DockerProvider.loadSnapshot(client: client, serviceID: serviceID, serviceName: "Portainer")
        #expect(snapshot.serviceID == serviceID)
        #expect(snapshot.serviceName == "Portainer")
        #expect(snapshot.hosts.count == 2)
        #expect(snapshot.hosts[0].error == .unexpectedStatus(500))
        #expect(snapshot.hosts[0].containers.isEmpty)
        #expect(snapshot.hosts[1].error == nil)
        #expect(snapshot.hosts[1].containers.map(\.name) == ["pihole", "certbot"])
        #expect(snapshot.stacks.map(\.name) == ["proxy", "media"])
    }

    @Test func timeoutOnOneHostIsIsolated() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .timeout,
            "/api/endpoints/2/docker/containers/json": .json(endpoint2Containers),
            "/api/stacks": .json("[]"),
        ])
        let snapshot = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        #expect(snapshot.hosts.map(\.error) == [.unreachable, nil])
    }

    @Test func unauthorizedOnContainersFailsWholeSnapshot() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .unauthorized,
            "/api/endpoints/2/docker/containers/json": .json(endpoint2Containers),
            "/api/stacks": .json(F.stacks),
        ])
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        }
        // Environments are queried in parallel, so the second host may already be in
        // flight; what matters is that nothing is asked twice (no retry on 401).
        let paths = await fake.receivedPaths
        #expect(paths.filter { $0 == "/api/endpoints/1/docker/containers/json" }.count == 1)
        #expect(paths.count == Set(paths).count)
    }

    @Test func forbiddenOnOneHostIsIsolated() async throws {
        // A 403 on one environment (no access to it) doesn't fail the others.
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .forbidden,
            "/api/endpoints/2/docker/containers/json": .json(endpoint2Containers),
            "/api/stacks": .json("[]"),
        ])
        let snapshot = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        #expect(snapshot.hosts.map(\.error) == [.forbidden, nil])
    }

    @Test func forbiddenOnEngineContainersFailsWholeSnapshot() async throws {
        // e.g. socket proxy with CONTAINERS=0: one refused request, then the service
        // is paused by the app instead of polled forever.
        let fake = FakeHTTPClient(routes: ["/containers/json": .forbidden])
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await DockerProvider.loadSnapshot(client: engineProvider(fake).client, serviceID: serviceID, serviceName: "E")
        }
        #expect(await fake.receivedPaths == ["/containers/json"])
    }

    @Test func forbiddenOnEveryPortainerHostFailsWholeSnapshot() async throws {
        // Nothing readable at all: the service must be paused, not polled forever.
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .forbidden,
            "/api/endpoints/2/docker/containers/json": .forbidden,
            "/api/stacks": .json("[]"),
        ])
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        }
    }

    @Test func reverseProxyBlockOnEveryPortainerHostFailsWholeSnapshot() async throws {
        // VPN off behind a "LAN only" proxy: pause the service instead of sending a
        // refused request per environment every cycle.
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(twoEndpoints),
            "/api/endpoints/1/docker/containers/json": .failure(HTTPClientError.blockedByProxy),
            "/api/endpoints/2/docker/containers/json": .failure(HTTPClientError.blockedByProxy),
            "/api/stacks": .json("[]"),
        ])
        await #expect(throws: ServiceProviderError.blockedByProxy) {
            _ = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        }
    }

    @Test func reverseProxyBlockOnEngineFailsWholeSnapshot() async throws {
        let fake = FakeHTTPClient(routes: ["/containers/json": .failure(HTTPClientError.blockedByProxy)])
        await #expect(throws: ServiceProviderError.blockedByProxy) {
            _ = try await DockerProvider.loadSnapshot(client: engineProvider(fake).client, serviceID: serviceID, serviceName: "E")
        }
        #expect(await fake.receivedPaths == ["/containers/json"])
    }

    @Test func downPortainerEndpointIsNotQueried() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(F.endpointsJSON([(1, "local", 1), (2, "storage-node", 2)])),
            "/api/endpoints/1/docker/containers/json": .json(endpoint1Containers),
            "/api/endpoints/2/docker/containers/json": .json(endpoint2Containers),
            "/api/stacks": .json(F.stacks),
        ])
        let snapshot = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        #expect(snapshot.hosts.count == 2)
        #expect(snapshot.hosts[1].host.status == .down)
        #expect(snapshot.hosts[1].error == .unreachable)
        #expect(snapshot.hosts[1].containers.isEmpty)
        let paths = await fake.receivedPaths
        #expect(!paths.contains { $0.hasPrefix("/api/endpoints/2/") })
        #expect(Set(paths) == ["/api/endpoints", "/api/endpoints/1/docker/containers/json", "/api/stacks"])
        #expect(paths.count == 3)
    }

    @Test(arguments: [FakeHTTPClient.Outcome.serverError, .forbidden, .unauthorized, .timeout, .json("not json")])
    func stacksFailureIsIgnored(stacksOutcome: FakeHTTPClient.Outcome) async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(F.endpointsJSON([(1, "local", 1)])),
            "/api/endpoints/1/docker/containers/json": .json(endpoint1Containers),
            "/api/stacks": stacksOutcome,
        ])
        let snapshot = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        #expect(snapshot.stacks.isEmpty)
        #expect(snapshot.hosts.first?.containers.count == 3)
    }

    @Test func hostsFailurePropagates() async {
        let fake = FakeHTTPClient(routes: ["/api/endpoints": .serverError])
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await DockerProvider.loadSnapshot(client: portainerProvider(fake).client, serviceID: serviceID, serviceName: "P")
        }
    }

    @Test func engineSnapshotHasSingleHostAndNoStacks() async throws {
        let fake = FakeHTTPClient(routes: ["/containers/json": .json(endpoint2Containers)])
        let snapshot = try await DockerProvider.loadSnapshot(client: engineProvider(fake).client, serviceID: serviceID, serviceName: "Docker")
        #expect(snapshot.hosts.map(\.host.name) == ["Docker"])
        #expect(snapshot.hosts.first?.containers.count == 2)
        #expect(snapshot.stacks.isEmpty)
        #expect(await fake.receivedPaths == ["/containers/json"])
    }
}
