import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import ProxmoxKit

private enum ClientFixtures {
    static let fakeToken = "test-user@pam!test-token=00000000-fake-0000-token"
    static let baseURL = URL(string: "https://proxmox.example.invalid:8006")!

    static let clusterResources = #"""
    {"data":[
      {"id":"node/node-1","type":"node","node":"node-1","status":"online","cpu":0.031,"maxcpu":8,
       "mem":5368709120,"maxmem":33554432000,"uptime":172800},
      {"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"name":"test-app","status":"running"},
      {"id":"lxc/200","type":"lxc","node":"node-1","vmid":200,"name":"dns","status":"running"}
    ]}
    """#

    static let nodeStatus = #"""
    {"data":{"cpu":0.0421,"uptime":172800,"pveversion":"pve-manager/8.2.4/faa83925c9641325",
     "kversion":"Linux 6.8.8-2-pve #1 SMP PREEMPT_DYNAMIC PMX 6.8.8-2 (2024-06-24T09:00Z)",
     "loadavg":["0.12","0.20","0.18"],
     "memory":{"used":5368709120,"total":33554432000,"free":28185722880},
     "rootfs":{"used":10737418240,"total":100000000000,"avail":89262581760,"free":89262581760},
     "cpuinfo":{"cpus":8,"model":"Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz","sockets":1,"cores":6}}}
    """#

    static let guestStatus = #"""
    {"data":{"status":"running","name":"test-app","vmid":100,"cpu":0.12,"cpus":2,
     "mem":2147483648,"maxmem":4294967296,"disk":0,"maxdisk":34359738368,"uptime":3600,
     "netin":123456,"netout":654321,"diskread":1000,"diskwrite":2000,"qmpstatus":"running",
     "ha":{"managed":0}}}
    """#

    static let guestRRD = #"""
    {"data":[
      {"time":1719900000,"cpu":0.05,"mem":268435456,"maxmem":536870912,"netin":10.5,"netout":3.2},
      {"time":1719901800,"cpu":0.07,"mem":270000000,"maxmem":536870912,"netin":11.0,"netout":3.0}
    ]}
    """#

    static let nodeRRD = #"""
    {"data":[
      {"time":1719300000,"cpu":0.04,"memused":5368709120,"memtotal":33554432000,"loadavg":0.2,"iowait":0.001},
      {"time":1719303600,"cpu":0.05,"memused":5400000000,"memtotal":33554432000,"loadavg":0.3,"iowait":0.002}
    ]}
    """#

    static let clusterTasks = #"""
    {"data":[
      {"upid":"UPID:pve:0000A1B2:00C3D4E5:66840000:vzdump:100:root@pam:","node":"node-1","type":"vzdump",
       "id":"100","user":"root@pam","starttime":1719926784,"endtime":1719926900,"status":"OK"},
      {"upid":"UPID:pve:0000A1B3:00C3D4E6:66840100:qmstart:101:root@pam:","node":"node-1","type":"qmstart",
       "id":"101","user":"root@pam","starttime":1719927040,"endtime":1719927041,"status":"start failed: QEMU exited with code 1"}
    ]}
    """#
}

private func makeClient(_ fake: FakeHTTPClient, baseURL: URL = ClientFixtures.baseURL) -> ProxmoxClient {
    ProxmoxClient(baseURL: baseURL, apiTokenValue: ClientFixtures.fakeToken, httpClient: fake)
}

private func onlySpec(_ fake: FakeHTTPClient) async throws -> HTTPRequestSpec {
    let specs = await fake.receivedSpecs
    #expect(specs.count == 1)
    return try #require(specs.first)
}

// MARK: - Nominal + paths

@Suite("ProxmoxClient endpoints")
struct ProxmoxClientEndpointTests {
    @Test func versionDecodesVersionAndTargetsVersionEndpoint() async throws {
        let fake = FakeHTTPClient.json(#"{"data":{"version":"8.2.4","release":"8.2","repoid":"faa83925c9641325"}}"#)
        let version = try await makeClient(fake).version()
        #expect(version == "8.2.4")
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/version")
    }

    @Test func clusterResourcesDecodesAndTargetsClusterResources() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.clusterResources)
        let resources = try await makeClient(fake).clusterResources()
        #expect(resources.map(\.id) == ["node/node-1", "qemu/100", "lxc/200"])
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/resources")
        #expect(spec.url.query == nil)
    }

    @Test func nodeStatusDecodesAndTargetsNodeStatus() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.nodeStatus)
        let status = try await makeClient(fake).nodeStatus(node: "node-2")
        #expect(status.cpuCount == 8)
        #expect(status.memoryTotal == 33_554_432_000)
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/nodes/node-2/status")
    }

    @Test func guestStatusDecodesAndTargetsQemuStatusCurrent() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.guestStatus)
        let status = try await makeClient(fake).guestStatus(node: "node-1", type: .qemu, vmid: 100)
        #expect(status.isRunning)
        #expect(status.vmid == 100)
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/nodes/node-1/qemu/100/status/current")
    }

    @Test func guestStatusTargetsLxcStatusCurrent() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.guestStatus)
        _ = try await makeClient(fake).guestStatus(node: "node-1", type: .lxc, vmid: 200)
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/nodes/node-1/lxc/200/status/current")
    }

    @Test func guestRRDTargetsLxcRRDDataWithDayAverageQuery() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.guestRRD)
        let points = try await makeClient(fake).guestRRD(node: "node-1", type: .lxc, vmid: 200, timeframe: .day)
        #expect(points.count == 2)
        #expect(points.first?.memoryTotal == 536_870_912)
        let spec = try await onlySpec(fake)
        #expect(spec.url.path.hasSuffix("/api2/json/nodes/node-1/lxc/200/rrddata"))
        let items = URLComponents(url: spec.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items == [URLQueryItem(name: "timeframe", value: "day"), URLQueryItem(name: "cf", value: "AVERAGE")])
        #expect(spec.url.absoluteString
            == "https://proxmox.example.invalid:8006/api2/json/nodes/node-1/lxc/200/rrddata?timeframe=day&cf=AVERAGE")
    }

    @Test func nodeRRDTargetsNodeRRDDataWithWeekAverageQuery() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.nodeRRD)
        let points = try await makeClient(fake).nodeRRD(node: "node-1", timeframe: .week)
        #expect(points.count == 2)
        #expect(points.first?.memoryUsed == 5_368_709_120)
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString
            == "https://proxmox.example.invalid:8006/api2/json/nodes/node-1/rrddata?timeframe=week&cf=AVERAGE")
    }

    @Test func clusterTasksDecodesAndTargetsClusterTasks() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.clusterTasks)
        let tasks = try await makeClient(fake).clusterTasks()
        #expect(tasks.count == 2)
        #expect(tasks[0].state == .ok)
        #expect(tasks[1].isFailed)
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/tasks")
    }

    @Test func everyRequestIsGetWithPVEAPITokenHeaderAndNoBody() async throws {
        let fake = FakeHTTPClient.json(#"{"data":[]}"#)
        _ = try await makeClient(fake).clusterTasks()
        let spec = try await onlySpec(fake)
        #expect(spec.method == .get)
        #expect(spec.body == nil)
        #expect(spec.headers == ["Authorization": "PVEAPIToken=\(ClientFixtures.fakeToken)"])
        #expect(!spec.redactedDescription.contains("00000000-fake-0000-token"))
    }

    @Test func trailingSlashInBaseURLDoesNotProduceDoubleSlash() async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.clusterResources)
        _ = try await makeClient(fake, baseURL: URL(string: "https://proxmox.example.invalid:8006/")!).clusterResources()
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/cluster/resources")
    }
}

// MARK: - Errors

@Suite("ProxmoxClient errors")
struct ProxmoxClientErrorTests {
    @Test func unauthorized401MapsToUnauthorizedWithoutRetry() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeClient(fake).clusterResources()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func forbidden403MapsToForbiddenWithoutRetry() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await makeClient(fake).nodeStatus(node: "node-1")
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func timeoutReportedAsUnreachableMapsToUnreachable() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unreachable))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake).clusterTasks()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func rawURLErrorTimeoutMapsToUnreachable() async {
        let fake = FakeHTTPClient(.failure(URLError(.timedOut)))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake).clusterResources()
        }
    }

    @Test func nonHTTPSURLErrorFromTransportMapsToUnreachable() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.nonHTTPSURL))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake, baseURL: URL(string: "http://proxmox.example.invalid:8006")!).version()
        }
    }

    @Test func invalidResponseFromTransportMapsToInvalidResponse() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.invalidResponse))
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).clusterResources()
        }
    }

    @Test func non200StatusMapsToUnexpectedStatus() async {
        let fake = FakeHTTPClient.json(#"{"data":null}"#, status: 500)
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await makeClient(fake).clusterResources()
        }
    }

    @Test func cancellationFromTransportIsRethrownAsIs() async {
        let fake = FakeHTTPClient(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) {
            _ = try await makeClient(fake).clusterResources()
        }
    }

    @Test(arguments: [
        "<html><body>502 Bad Gateway</body></html>",
        #"{"data":[{"id":"node/node-1""#,
        #"{"data":"not a list"}"#,
    ])
    func invalidJSONOnListEndpointThrowsDecodingFailed(body: String) async {
        let fake = FakeHTTPClient.json(body)
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).clusterResources()
        }
    }

    @Test func invalidJSONOnObjectEndpointThrowsDecodingFailed() async {
        let fake = FakeHTTPClient.json("<html>not json</html>")
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).nodeStatus(node: "node-1")
        }
    }

    @Test func versionWithoutVersionFieldThrowsDecodingFailed() async {
        let fake = FakeHTTPClient.json(#"{"data":{}}"#)
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).version()
        }
    }
}

// MARK: - Empty responses

@Suite("ProxmoxClient empty responses")
struct ProxmoxClientEmptyResponseTests {
    @Test func emptyBodyOnListEndpointThrowsDecodingFailed() async {
        let fake = FakeHTTPClient(.response(status: 200, body: Data()))
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).clusterResources()
        }
    }

    @Test func emptyBodyOnObjectEndpointThrowsDecodingFailed() async {
        let fake = FakeHTTPClient(.response(status: 200, body: Data()))
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).guestStatus(node: "node-1", type: .qemu, vmid: 100)
        }
    }

    @Test func nullDataOnListEndpointsReturnsEmptyList() async throws {
        let client = makeClient(FakeHTTPClient.json(#"{"data":null}"#))
        #expect(try await client.clusterResources().isEmpty)
        #expect(try await client.clusterTasks().isEmpty)
        #expect(try await client.nodeRRD(node: "node-1", timeframe: .hour).isEmpty)
        #expect(try await client.guestRRD(node: "node-1", type: .qemu, vmid: 100, timeframe: .day).isEmpty)
    }

    @Test func emptyDataArrayOnListEndpointsReturnsEmptyList() async throws {
        let client = makeClient(FakeHTTPClient.json(#"{"data":[]}"#))
        #expect(try await client.clusterResources().isEmpty)
        #expect(try await client.clusterTasks().isEmpty)
    }

    @Test func nullDataOnNodeStatusThrowsInvalidResponse() async {
        let fake = FakeHTTPClient.json(#"{"data":null}"#)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).nodeStatus(node: "node-1")
        }
    }

    @Test func nullDataOnGuestStatusThrowsInvalidResponse() async {
        let fake = FakeHTTPClient.json(#"{"data":null}"#)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).guestStatus(node: "node-1", type: .lxc, vmid: 200)
        }
    }

    @Test func nullDataOnVersionThrowsInvalidResponse() async {
        let fake = FakeHTTPClient.json(#"{"data":null}"#)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).version()
        }
    }
}

// MARK: - Node name validation

@Suite("ProxmoxClient node name validation")
struct ProxmoxClientNodeNameTests {
    @Test(arguments: ["node-1", "node-2", "node_3.example.invalid"])
    func validNodeNameIsAcceptedAndUsedVerbatim(node: String) async throws {
        let fake = FakeHTTPClient.json(ClientFixtures.nodeStatus)
        _ = try await makeClient(fake).nodeStatus(node: node)
        let spec = try await onlySpec(fake)
        #expect(spec.url.absoluteString == "https://proxmox.example.invalid:8006/api2/json/nodes/\(node)/status")
    }

    @Test(arguments: ["../x", "a/b", "", "é", ".", "..", "node-1?x=1", "node-1%2F"])
    func invalidNodeNameIsRejectedBeforeAnyRequest(node: String) async {
        let fake = FakeHTTPClient.json(ClientFixtures.nodeStatus)
        let client = makeClient(fake)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client.nodeStatus(node: node)
        }
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client.guestStatus(node: node, type: .qemu, vmid: 100)
        }
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client.guestRRD(node: node, type: .lxc, vmid: 200, timeframe: .day)
        }
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client.nodeRRD(node: node, timeframe: .week)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }
}
