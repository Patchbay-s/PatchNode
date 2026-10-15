import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import ProxmoxKit

// MARK: - Fixtures

private enum ProviderFixtures {
    static let fakeToken = "test-user@pam!test-token=00000000-fake-0000-token"
    static let fakeSecret = "00000000-fake-0000-token"
    static let baseURL = URL(string: "https://proxmox.example.invalid:8006")!
    static let baseURLWithTrailingSlash = URL(string: "https://proxmox.example.invalid:8006/")!

    static let versionJSON = Data(#"{"data":{"version":"8.2.4","release":"8.2","repoid":"faa83925c9641325"}}"#.utf8)
    /// What a token with PVEAuditor sees: the health check reads this one endpoint.
    static let resourcesJSON = Data(#"{"data":[{"id":"node/node-1","type":"node","node":"node-1","status":"online","maxcpu":8,"maxmem":34359738368},{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"status":"running"}]}"#.utf8)
    static let invalidJSON = Data("<html>not json</html>".utf8)

    /// Two-node PVE 8 cluster: pve online, node-b offline; 2 VMs (1 running) + 1 template,
    /// 2 LXC (1 running); local-lvm at 90 % (alert), local at 40 %.
    static let clusterResourcesJSON = Data(#"""
    {"data":[
      {"id":"node/node-1","type":"node","node":"node-1","status":"online","cpu":0.042,"maxcpu":8,
       "mem":6442450944,"maxmem":33554432000,"disk":10737418240,"maxdisk":100000000000,"uptime":86400,"level":""},
      {"id":"node/node-b","type":"node","node":"node-b","status":"offline"},
      {"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"name":"test-app","status":"running",
       "cpu":0.12,"maxcpu":2,"mem":2147483648,"maxmem":4294967296,"template":0,"tags":"prod;web"},
      {"id":"qemu/101","type":"qemu","node":"node-1","vmid":101,"name":"test-database","status":"stopped",
       "maxcpu":4,"maxmem":8589934592,"template":0},
      {"id":"qemu/9000","type":"qemu","node":"node-1","vmid":9000,"name":"test-vm-template","status":"stopped","template":1},
      {"id":"lxc/200","type":"lxc","node":"node-1","vmid":200,"name":"dns","status":"running","maxmem":536870912},
      {"id":"lxc/201","type":"lxc","node":"node-1","vmid":201,"name":"proxy","status":"stopped","maxmem":536870912},
      {"id":"storage/node-1/local","type":"storage","node":"node-1","storage":"local","status":"available",
       "disk":40000000000,"maxdisk":100000000000,"shared":0,"plugintype":"dir","content":"iso,vztmpl,backup"},
      {"id":"storage/node-1/local-lvm","type":"storage","node":"node-1","storage":"local-lvm","status":"available",
       "disk":90000000000,"maxdisk":100000000000,"shared":0,"plugintype":"lvmthin","content":"images,rootdir"},
      {"id":"pool/prod","type":"pool","pool":"prod"}
    ]}
    """#.utf8)
}

private func makeProvider(
    _ client: FakeHTTPClient,
    baseURL: URL = ProviderFixtures.baseURL,
    id: UUID = UUID(),
    displayName: String = "PVE test"
) -> ProxmoxProvider {
    ProxmoxProvider(id: id, displayName: displayName, baseURL: baseURL, apiTokenValue: ProviderFixtures.fakeToken, httpClient: client)
}

// MARK: - Identity

@Suite("ProxmoxProvider identity")
struct ProxmoxProviderIdentityTests {
    @Test func exposesIdKindAndDisplayNameAsGiven() {
        let id = UUID()
        let provider = makeProvider(FakeHTTPClient(.response(status: 200, body: ProviderFixtures.versionJSON)), id: id, displayName: "Mon cluster")
        #expect(provider.id == id)
        #expect(provider.kind == .proxmoxVE)
        #expect(provider.displayName == "Mon cluster")
    }
}

// MARK: - healthCheck

@Suite("ProxmoxProvider.healthCheck")
struct ProxmoxProviderHealthCheckTests {
    @Test func healthCheckReturnsOkWithOneRequest() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.resourcesJSON))
        let status = try await makeProvider(client).healthCheck()
        guard case .ok = status else {
            Issue.record("Expected .ok, got \(status)")
            return
        }
        // One request checks the token, the rights and the reachability.
        #expect(await client.receivedSpecs.map(\.url.path) == ["/api2/json/cluster/resources"])
    }

    // BUGS.md ÉLEVÉ: Privilege Separation without a permission → bare nodes only.
    @Test func healthCheckReportsTokenWithoutRights() async throws {
        let bare = #"{"data":[{"id":"node/node-1","type":"node","node":"node-1","status":"online"}]}"#
        let client = FakeHTTPClient(.response(status: 200, body: Data(bare.utf8)))
        let status = try await makeProvider(client).healthCheck()
        guard case .degraded(let reason) = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
        #expect(reason == ProxmoxProvider.insufficientRightsReason)
    }

    @Test func emptyClusterIsNotReportedAsMissingRights() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: Data(#"{"data":[]}"#.utf8)))
        guard case .ok = try await makeProvider(client).healthCheck() else {
            Issue.record("Expected .ok")
            return
        }
    }

    @Test func lacksPrivilegesOnlyForBareNodesWithoutAnything() {
        let bareNode = ProxmoxResource(id: "node/node-1", kind: .node, node: "node-1", status: "online")
        let fullNode = ProxmoxResource(id: "node/node-1", kind: .node, node: "node-1", status: "online", maxCPU: 8, maxMemory: 1)
        let storage = ProxmoxResource(id: "storage/node-1/local", kind: .storage, node: "node-1", storage: "local")
        #expect(ProxmoxInventory.lacksPrivileges([bareNode]))
        #expect(!ProxmoxInventory.lacksPrivileges([]))
        #expect(!ProxmoxInventory.lacksPrivileges([fullNode]))
        #expect(!ProxmoxInventory.lacksPrivileges([bareNode, storage]))
    }

    @Test func healthCheckReportsReverseProxyBlockAsUnreachable() async throws {
        let client = FakeHTTPClient(.failure(HTTPClientError.blockedByProxy))
        let status = try await makeProvider(client).healthCheck()
        guard case .unreachable(let error) = status else {
            Issue.record("Expected .unreachable, got \(status)")
            return
        }
        #expect(error as? ServiceProviderError == .blockedByProxy)
        #expect(await client.receivedSpecs.count == 1)
    }

    @Test func healthCheckCallsClusterResourcesEndpoint() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.resourcesJSON))
        _ = try await makeProvider(client).healthCheck()
        let spec = try #require(await client.receivedSpecs.first)
        #expect(spec.method == .get)
        #expect(spec.headers["Authorization"] == "PVEAPIToken=\(ProviderFixtures.fakeToken)")
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/resources")
    }

    @Test func healthCheckReturnsUnauthorizedOn401WithoutRetry() async throws {
        let client = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        let status = try await makeProvider(client).healthCheck()
        guard case .unauthorized = status else {
            Issue.record("Expected .unauthorized, got \(status)")
            return
        }
        #expect(await client.receivedSpecs.count == 1)
    }

    @Test func healthCheckReturnsUnauthorizedOn403WithoutRetry() async throws {
        let client = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        let status = try await makeProvider(client).healthCheck()
        guard case .unauthorized = status else {
            Issue.record("Expected .unauthorized, got \(status)")
            return
        }
        #expect(await client.receivedSpecs.count == 1)
    }

    @Test func healthCheckReturnsUnreachableWhenClientReportsUnreachable() async throws {
        let client = FakeHTTPClient(.failure(HTTPClientError.unreachable))
        let status = try await makeProvider(client).healthCheck()
        guard case .unreachable = status else {
            Issue.record("Expected .unreachable, got \(status)")
            return
        }
    }

    @Test func healthCheckReturnsUnreachableOnTimeout() async throws {
        let client = FakeHTTPClient(.failure(URLError(.timedOut)))
        let status = try await makeProvider(client).healthCheck()
        guard case .unreachable = status else {
            Issue.record("Expected .unreachable, got \(status)")
            return
        }
    }

    @Test func healthCheckReturnsDegradedContaining500On500() async throws {
        let client = FakeHTTPClient(.response(status: 500, body: Data()))
        let status = try await makeProvider(client).healthCheck()
        guard case let .degraded(reason) = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
        #expect(reason.contains("500"))
    }

    @Test func healthCheckReturnsDegradedOnInvalidJSONWith200() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.invalidJSON))
        let status = try await makeProvider(client).healthCheck()
        guard case .degraded = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
    }

    @Test func healthCheckRethrowsCancellation() async {
        let client = FakeHTTPClient(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) {
            _ = try await makeProvider(client).healthCheck()
        }
    }
}

// MARK: - summary

@Suite("ProxmoxProvider.summary")
struct ProxmoxProviderSummaryTests {
    @Test func summaryReportsNodesOnlineOverTotalAsHeadline() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.clusterResourcesJSON))
        let summary = try await makeProvider(client).summary()
        #expect(summary.headline == "1/2")
    }

    @Test func summaryDetailsCountNodesGuestsAndStorageAlerts() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.clusterResourcesJSON))
        let summary = try await makeProvider(client).summary()
        #expect(summary.details == [
            "nodesOnline": "1",
            "nodesTotal": "2",
            "vmsRunning": "1",
            "vmsTotal": "2",
            "containersRunning": "1",
            "containersTotal": "2",
            "storagesAboveThreshold": "1",
        ])
    }

    @Test func summaryOfEmptyClusterIsZeroOverZero() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: Data(#"{"data":[]}"#.utf8)))
        let summary = try await makeProvider(client).summary()
        #expect(summary.headline == "0/0")
        #expect(summary.details["vmsTotal"] == "0")
    }

    @Test func summaryThrowsDecodingFailedOnInvalidJSONWith200() async {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.invalidJSON))
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeProvider(client).summary()
        }
    }

    @Test func summaryThrowsUnauthorizedOn401WithoutRetry() async {
        let client = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeProvider(client).summary()
        }
        #expect(await client.receivedSpecs.count == 1)
    }

    @Test func summaryThrowsForbiddenOn403WithoutRetry() async {
        let client = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await makeProvider(client).summary()
        }
        #expect(await client.receivedSpecs.count == 1)
    }

    @Test func summaryThrowsUnexpectedStatusOn500() async {
        let client = FakeHTTPClient(.response(status: 500, body: ProviderFixtures.clusterResourcesJSON))
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await makeProvider(client).summary()
        }
    }

    @Test func summaryThrowsUnreachableWhenClientReportsUnreachable() async {
        let client = FakeHTTPClient(.failure(HTTPClientError.unreachable))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeProvider(client).summary()
        }
    }

    @Test func summaryThrowsUnreachableOnTimeout() async {
        let client = FakeHTTPClient(.failure(URLError(.timedOut)))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeProvider(client).summary()
        }
    }

    @Test func summaryThrowsInvalidResponseWhenClientReportsInvalidResponse() async {
        let client = FakeHTTPClient(.failure(HTTPClientError.invalidResponse))
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeProvider(client).summary()
        }
    }
}

// MARK: - Request construction

@Suite("ProxmoxProvider request")
struct ProxmoxProviderRequestTests {
    private func sentSummarySpec(baseURL: URL) async throws -> HTTPRequestSpec {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.clusterResourcesJSON))
        _ = try await makeProvider(client, baseURL: baseURL).summary()
        let specs = await client.receivedSpecs
        #expect(specs.count == 1)
        return try #require(specs.first)
    }

    @Test func summaryRequestIsGetWithPVEAPITokenAuthorizationHeader() async throws {
        let spec = try await sentSummarySpec(baseURL: ProviderFixtures.baseURL)
        #expect(spec.method == .get)
        #expect(spec.headers["Authorization"] == "PVEAPIToken=\(ProviderFixtures.fakeToken)")
        #expect(spec.body == nil)
    }

    @Test func summaryRequestTargetsClusterResourcesEndpoint() async throws {
        let spec = try await sentSummarySpec(baseURL: ProviderFixtures.baseURL)
        #expect(spec.url.scheme == "https")
        #expect(spec.url.host == "proxmox.example.invalid")
        #expect(spec.url.port == 8006)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/resources")
    }

    @Test func requestPathHasNoDoubleSlashWhenBaseURLHasTrailingSlash() async throws {
        let spec = try await sentSummarySpec(baseURL: ProviderFixtures.baseURLWithTrailingSlash)
        #expect(!spec.url.absoluteString.contains("//api2"))
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/resources")
    }

    @Test func healthCheckPathHasNoDoubleSlashWhenBaseURLHasTrailingSlash() async throws {
        let client = FakeHTTPClient(.response(status: 200, body: ProviderFixtures.resourcesJSON))
        _ = try await makeProvider(client, baseURL: ProviderFixtures.baseURLWithTrailingSlash).healthCheck()
        let spec = try #require(await client.receivedSpecs.first)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/resources")
    }

    @Test func redactedDescriptionOfSentRequestDoesNotLeakToken() async throws {
        let spec = try await sentSummarySpec(baseURL: ProviderFixtures.baseURL)
        let description = spec.redactedDescription
        #expect(!description.contains(ProviderFixtures.fakeToken))
        #expect(!description.contains(ProviderFixtures.fakeSecret))
        #expect(!description.contains("PVEAPIToken"))
        #expect(description.contains("<redacted>"))
    }
}
