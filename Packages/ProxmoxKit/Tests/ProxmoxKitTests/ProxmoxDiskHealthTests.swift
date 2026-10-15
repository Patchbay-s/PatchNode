import Foundation
import Synchronization
import Testing
import PatchNodeCore
@testable import ProxmoxKit

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

struct ProxmoxDiskModelTests {
    @Test func diskHealthAndWearout() throws {
        let nvme = try decode(ProxmoxDisk.self, #"{"devpath":"/dev/nvme0n1","model":"Samsung SSD 980 PRO","type":"nvme","size":1000204886016,"health":"PASSED","wearout":96,"used":"ZFS"}"#)
        #expect(nvme.health == .passed)
        #expect(nvme.lifeLeft == 96)
        #expect(nvme.usage == "ZFS")
        #expect(nvme.level == .ok)

        let sas = try decode(ProxmoxDisk.self, #"{"devpath":"/dev/sdc","health":"OK","wearout":"N/A","size":"4000787030016"}"#)
        #expect(sas.health == .passed)
        #expect(sas.lifeLeft == nil)
        #expect(sas.size == 4_000_787_030_016)

        let failed = try decode(ProxmoxDisk.self, #"{"devpath":"/dev/sdb","health":"FAILED"}"#)
        #expect(failed.level == .critical)

        let worn = try decode(ProxmoxDisk.self, #"{"devpath":"/dev/nvme1n1","health":"PASSED","wearout":"10"}"#)
        #expect(worn.lifeLeft == 10)
        #expect(worn.level == .warning)

        let usb = try decode(ProxmoxDisk.self, #"{"devpath":"/dev/sdd","health":"UNKNOWN","wearout":250}"#)
        #expect(usb.health == .unknown)
        #expect(usb.lifeLeft == nil)
        #expect(usb.level == .ok)

        let noHealth = try decode(ProxmoxDisk.self, #"{"devpath":"/dev/sde","health":null,"size":-5}"#)
        #expect(noHealth.health == .unknown)
        #expect(noHealth.size == 0)

        #expect(throws: (any Error).self) { try decode(ProxmoxDisk.self, #"{"model":"no path"}"#) }
    }

    @Test func zfsPoolLevels() throws {
        let online = try decode(ProxmoxZFSPool.self, #"{"name":"rpool","health":"ONLINE","size":1000,"alloc":400,"frag":12}"#)
        #expect(online.level == .ok)
        #expect(online.usage == 0.4)
        #expect(online.fragmentation == 12)

        #expect(ProxmoxZFSPool(name: "p", health: "online", size: 1000, allocated: 800).level == .warning)
        #expect(ProxmoxZFSPool(name: "p", health: "ONLINE", size: 1000, allocated: 900).level == .critical)
        #expect(ProxmoxZFSPool(name: "p", health: "DEGRADED", size: 1000, allocated: 100).level == .warning)
        #expect(ProxmoxZFSPool(name: "p", health: "DEGRADED", size: 1000, allocated: 950).level == .critical)
        #expect(ProxmoxZFSPool(name: "p", health: "FAULTED").level == .critical)
        #expect(ProxmoxZFSPool(name: "p", health: "SUSPENDED").level == .critical)
        #expect(ProxmoxZFSPool(name: "p", health: "ONLINE", size: 0, allocated: 0).usage == nil)

        let missingHealth = try decode(ProxmoxZFSPool.self, #"{"name":"tank"}"#)
        #expect(missingHealth.health == "UNKNOWN")
        #expect(missingHealth.level == .critical)
        #expect(throws: (any Error).self) { try decode(ProxmoxZFSPool.self, #"{"health":"ONLINE"}"#) }
    }

    @Test func reportSortsWorstFirstAndListsIssues() {
        let node = ProxmoxDiskHealth.Node(
            name: "node-a",
            disks: [
                ProxmoxDisk(devpath: "/dev/sda", health: .passed),
                ProxmoxDisk(devpath: "/dev/sdb", health: .failed),
                ProxmoxDisk(devpath: "/dev/nvme0n1", health: .passed, lifeLeft: 5),
            ],
            pools: [ProxmoxZFSPool(name: "rpool", health: "ONLINE", size: 10, allocated: 1), ProxmoxZFSPool(name: "tank", health: "DEGRADED")]
        )
        #expect(node.disks.map(\.devpath) == ["/dev/sdb", "/dev/nvme0n1", "/dev/sda"])
        #expect(node.pools.map(\.name) == ["tank", "rpool"])
        #expect(node.level == .critical)
        let healthy = ProxmoxDiskHealth.Node(name: "node-b", disks: [ProxmoxDisk(devpath: "/dev/sda", health: .passed)], pools: [])
        let report = ProxmoxDiskHealth(nodes: [healthy, node])
        #expect(report.nodes.map(\.name) == ["node-a", "node-b"])
        #expect(report.level == .critical)
        #expect(report.issues.map(\.id) == ["node-a/disk/dev/sdb", "node-a/disk/dev/nvme0n1", "node-a/pool/tank"])
        #expect(!report.hasUnavailableParts)
        #expect(ProxmoxDiskHealth(nodes: []).level == .ok)
    }
}

/// 403 on the disk list (token without Sys.Audit on the node).
private struct RefusingDisks: DemoResponder {
    let status: Int
    let inner = ProxmoxDemoResponder()
    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        if request.path.hasSuffix("/disks/list") { return .json(#"{"data":null}"#, status: status) }
        return inner.respond(to: request, now: now)
    }
}

/// Counts the requests after a reverse-proxy block on the first disk list.
private final class ProxyBlockingDisks: DemoResponder {
    let inner = ProxmoxDemoResponder()
    let diskRequests = Mutex(0)
    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        if request.path.contains("/disks/") {
            diskRequests.withLock { $0 += 1 }
            return DemoResponse(status: 403, contentType: "text/html", body: Data("<html><body><h1>403 Forbidden</h1></body></html>".utf8))
        }
        return inner.respond(to: request, now: now)
    }
}

@Suite(.serialized)
struct ProxmoxDiskHealthLoadTests {
    private func client(host: String) -> ProxmoxClient {
        ProxmoxClient(baseURL: URL(string: "https://\(host):8006")!, apiTokenValue: "test-user@pam!test-token=0",
                      httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), backoff: 0, label: nil, log: nil))
    }

    @Test func demoClusterShowsItsProblems() async throws {
        let host = "pve-disks-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(ProxmoxDemoResponder(), host: host)
        let client = client(host: host)
        let report = try await ProxmoxDiskHealth.load(client: client, resources: try await client.clusterResources())
        #expect(report.nodes.map(\.name) == ["node-a", "node-b"])
        #expect(!report.hasUnavailableParts)
        #expect(report.level == .critical)
        let issues = report.issues.map(\.id)
        #expect(issues.contains("node-a/disk/dev/sdb"))
        #expect(issues.contains("node-a/pool/data"))
        #expect(issues.contains("node-b/disk/dev/nvme0n1"))
        #expect(issues.contains("node-b/pool/rpool"))
        #expect(report.nodes[1].disks.first { $0.devpath == "/dev/nvme0n1" }?.lifeLeft == 8)
    }

    @Test func refusedDiskListOnlyEmptiesThatPart() async throws {
        let host = "pve-disks-403-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(RefusingDisks(status: 403), host: host)
        let client = client(host: host)
        let report = try await ProxmoxDiskHealth.load(client: client, resources: try await client.clusterResources())
        #expect(report.nodes.allSatisfy { $0.unavailable == [.disks] && $0.disks.isEmpty })
        #expect(report.nodes.allSatisfy { !$0.pools.isEmpty })
        #expect(report.hasUnavailableParts)
    }

    @Test func rejectedTokenStops() async throws {
        let host = "pve-disks-401-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(RefusingDisks(status: 401), host: host)
        let client = client(host: host)
        let resources = try await client.clusterResources()
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await ProxmoxDiskHealth.load(client: client, resources: resources)
        }
    }

    @Test func proxyBlockStopsAfterOneRequest() async throws {
        let host = "pve-disks-proxy-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        let responder = ProxyBlockingDisks()
        DemoServer.register(responder, host: host)
        let client = client(host: host)
        let resources = try await client.clusterResources()
        await #expect(throws: ServiceProviderError.blockedByProxy) {
            _ = try await ProxmoxDiskHealth.load(client: client, resources: resources)
        }
        #expect(responder.diskRequests.withLock { $0 } == 1)
    }

    @Test func offlineNodesAreSkipped() async throws {
        let resources = [
            ProxmoxResource(id: "node/a", kind: .node, node: "a", status: "offline"),
            ProxmoxResource(id: "storage/a/local", kind: .storage, node: "a", status: "available", storage: "local"),
        ]
        let host = "pve-disks-offline-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(ProxmoxDemoResponder(), host: host)
        let report = try await ProxmoxDiskHealth.load(client: client(host: host), resources: resources)
        #expect(report.nodes.isEmpty)
    }
}
