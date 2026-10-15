import Foundation
import Synchronization
import Testing
import PatchNodeCore
@testable import ProxmoxKit

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

struct ProxmoxBackupModelTests {
    @Test func jobSelectionAndSchedule() throws {
        let all = try decode(ProxmoxBackupJob.self, #"{"id":"backup-1","enabled":1,"schedule":"03:00","storage":"nas","all":1,"exclude":"203,9000","next-run":1790000000}"#)
        #expect(all.selection == .all(excluding: [203, 9000]))
        #expect(all.isEnabled)
        #expect(all.nextRun == Date(timeIntervalSince1970: 1_790_000_000))
        let some = try decode(ProxmoxBackupJob.self, #"{"id":"b2","enabled":"0","vmid":"100,101","starttime":"04:00","dow":"sun"}"#)
        #expect(some.selection == .guests([100, 101]))
        #expect(!some.isEnabled)
        #expect(some.schedule == "sun 04:00")
        let pool = try decode(ProxmoxBackupJob.self, #"{"id":"b3","pool":"prod"}"#)
        #expect(pool.selection == .pool("prod"))
        #expect(throws: (any Error).self) { try decode(ProxmoxBackupJob.self, #"{"enabled":1}"#) }
    }

    @Test func archivesAndUnprotectedGuests() throws {
        let file = try decode(ProxmoxBackupFile.self, #"{"volid":"nas:backup/vzdump-qemu-100-2026_09_30-03_00_00.vma.zst","vmid":"100","ctime":1790000000,"size":123,"protected":1}"#)
        #expect(file.vmid == 100)
        #expect(file.isProtected)
        let guest = try decode(ProxmoxUnprotectedGuest.self, #"{"vmid":203,"name":"sandbox","type":"lxc"}"#)
        #expect(guest.type == .lxc)
    }

    @Test func sharedStorageIsListedOnceAndOfflineNodesAreSkipped() {
        let resources: [ProxmoxResource] = [
            ProxmoxResource(id: "node/a", kind: .node, node: "a", status: "online"),
            ProxmoxResource(id: "node/b", kind: .node, node: "b", status: "offline"),
            ProxmoxResource(id: "storage/a/local", kind: .storage, node: "a", status: "available", storage: "local", content: ["iso", "backup"]),
            ProxmoxResource(id: "storage/a/lvm", kind: .storage, node: "a", status: "available", storage: "lvm", content: ["images"]),
            ProxmoxResource(id: "storage/a/nas", kind: .storage, node: "a", status: "available", storage: "nas", isShared: true, content: ["backup"]),
            ProxmoxResource(id: "storage/b/nas", kind: .storage, node: "b", status: "available", storage: "nas", isShared: true, content: ["backup"]),
            ProxmoxResource(id: "storage/b/local", kind: .storage, node: "b", status: "available", storage: "local", content: ["backup"]),
        ]
        let list = ProxmoxNativeBackups.storagesToList(resources).map { "\($0.node)/\($0.storage)" }
        #expect(list == ["a/local", "a/nas"])
    }

    @Test func latestArchivePerGuestStaleAndFailedTasks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resources: [ProxmoxResource] = [
            ProxmoxResource(id: "qemu/100", kind: .guest(.qemu), node: "a", vmid: 100, name: "web"),
            ProxmoxResource(id: "qemu/101", kind: .guest(.qemu), node: "a", vmid: 101, name: "db"),
            ProxmoxResource(id: "lxc/102", kind: .guest(.lxc), node: "a", vmid: 102, name: "never"),
            ProxmoxResource(id: "qemu/9000", kind: .guest(.qemu), node: "a", vmid: 9000, name: "tpl", isTemplate: true),
        ]
        let files = [
            ProxmoxBackupFile(volid: "nas:1", vmid: 100, created: now.addingTimeInterval(-3_600)),
            ProxmoxBackupFile(volid: "nas:2", vmid: 100, created: now.addingTimeInterval(-90_000)),
            ProxmoxBackupFile(volid: "nas:1", vmid: 100, created: now.addingTimeInterval(-3_600)),
            ProxmoxBackupFile(volid: "nas:3", vmid: 101, created: now.addingTimeInterval(-4 * 86_400)),
        ]
        let tasks = [
            ProxmoxTask(id: "UPID:a:1", type: "vzdump", targetID: "101", startTime: now.addingTimeInterval(-7_200), endTime: now, rawStatus: "job errors"),
            ProxmoxTask(id: "UPID:a:2", type: "vzdump", startTime: now.addingTimeInterval(-3 * 86_400), endTime: now, rawStatus: "job errors"),
            ProxmoxTask(id: "UPID:a:3", type: "qmstart", startTime: now, endTime: now, rawStatus: "failed"),
        ]
        let report = ProxmoxNativeBackups(resources: resources, jobs: [], unprotected: [], files: files, tasks: tasks, now: now)
        #expect(report.guests.map(\.guest.vmid) == [102, 101, 100])
        #expect(report.guests[2].count == 2)
        #expect(report.guests[2].latest?.volid == "nas:1")
        #expect(report.isStale(report.guests[0], now: now))
        #expect(report.isStale(report.guests[1], now: now))
        #expect(!report.isStale(report.guests[2], now: now))
        #expect(report.failedTasks.map(\.id) == ["UPID:a:1"])
    }
}

/// Reverse-proxy block (HTML 403) on the first backup request; counts the
/// storage listings that still arrive.
private final class ProxyBlockingJobs: DemoResponder {
    let inner = ProxmoxDemoResponder()
    let storageRequests = Mutex(0)
    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        if request.path.hasSuffix("/cluster/backup") {
            return DemoResponse(status: 403, contentType: "text/html", body: Data("<html><body><h1>403 Forbidden</h1></body></html>".utf8))
        }
        if request.path.contains("/storage/") { storageRequests.withLock { $0 += 1 } }
        return inner.respond(to: request, now: now)
    }
}

private struct RefusingJobs: DemoResponder {
    let status: Int
    let inner = ProxmoxDemoResponder()
    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        if request.path.hasSuffix("/cluster/backup") { return .json(#"{"data":null}"#, status: status) }
        return inner.respond(to: request, now: now)
    }
}

@Suite(.serialized)
struct ProxmoxNativeBackupsLoadTests {
    private func client(host: String) -> ProxmoxClient {
        ProxmoxClient(baseURL: URL(string: "https://\(host):8006")!, apiTokenValue: "test-user@pam!test-token=0",
                      httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), backoff: 0, label: nil, log: nil))
    }

    @Test func demoClusterLoadsEveryPart() async throws {
        let host = "pve-backups-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(ProxmoxDemoResponder(), host: host)
        let client = client(host: host)
        let resources = try await client.clusterResources()
        let tasks = try await client.clusterTasks()
        let report = try await ProxmoxNativeBackups.load(client: client, resources: resources, tasks: tasks)
        #expect(report.unavailable.isEmpty)
        #expect(report.jobs.count == 2)
        #expect(report.unprotected.map(\.vmid) == [203])
        #expect(report.guests.contains { $0.guest.vmid == 102 && report.isStale($0) })
        #expect(report.guests.contains { $0.guest.vmid == 100 && !report.isStale($0) && $0.count == 7 })
        #expect(!report.failedTasks.isEmpty)
    }

    @Test func refusedJobsOnlyEmptyThatPart() async throws {
        let host = "pve-403-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(RefusingJobs(status: 403), host: host)
        let client = client(host: host)
        let resources = try await client.clusterResources()
        let report = try await ProxmoxNativeBackups.load(client: client, resources: resources, tasks: [])
        #expect(report.unavailable == [.jobs])
        #expect(report.jobs.isEmpty)
        #expect(!report.guests.isEmpty)
    }

    @Test func proxyBlockStopsBeforeAnyOtherRequest() async throws {
        let host = "pve-proxy-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        let responder = ProxyBlockingJobs()
        DemoServer.register(responder, host: host)
        let client = client(host: host)
        let resources = try await client.clusterResources()
        await #expect(throws: ServiceProviderError.blockedByProxy) {
            _ = try await ProxmoxNativeBackups.load(client: client, resources: resources, tasks: [])
        }
        #expect(responder.storageRequests.withLock { $0 } == 0)
    }

    @Test func rejectedTokenStops() async throws {
        let host = "pve-401-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(RefusingJobs(status: 401), host: host)
        let client = client(host: host)
        let resources = try await client.clusterResources()
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await ProxmoxNativeBackups.load(client: client, resources: resources, tasks: [])
        }
    }
}
