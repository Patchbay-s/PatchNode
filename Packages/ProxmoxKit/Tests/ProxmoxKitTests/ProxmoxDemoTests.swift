import Foundation
import Testing
import PatchNodeCore
@testable import ProxmoxKit

/// The demo cluster goes through the real clients, decoders and inventory.
@Suite(.serialized)
struct ProxmoxDemoTests {
    let pve = DemoCatalog.services.first { $0.kind == .proxmoxVE }!
    let pbs = DemoCatalog.services.first { $0.kind == .proxmoxBackupServer }!

    init() {
        DemoServer.register(ProxmoxDemoResponder(), host: DemoCatalog.host(for: .proxmoxVE))
        DemoServer.register(PBSDemoResponder(), host: DemoCatalog.host(for: .proxmoxBackupServer))
    }

    private func client() -> ProxmoxClient {
        ProxmoxClient(baseURL: pve.url, apiTokenValue: pve.credential,
                      httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil))
    }

    @Test func clusterLoadsWithNodesGuestsStoragesAndTasks() async throws {
        let snapshot = try await ProxmoxServiceSnapshot.load(serviceID: pve.id, serviceName: pve.name, client: client())
        let inventory = ProxmoxInventory(snapshots: [snapshot])
        #expect(inventory.nodes.count == 2)
        #expect(inventory.guests.count >= 6)
        #expect(!inventory.storages.isEmpty)
        #expect(!snapshot.tasksUnavailable)
        #expect(inventory.overview.recentFailedTasks >= 1)
        #expect(!ProxmoxInventory.lacksPrivileges(snapshot.resources))
        let conditions = inventory.watchedConditions()
        #expect(!conditions.isEmpty)
        #expect(conditions.allSatisfy { $0.kind == .backupFailed && $0.key.hasPrefix("pve|") })
        // A day later the failed backups are no longer news.
        #expect(inventory.watchedConditions(now: .now.addingTimeInterval(3 * 86_400)).isEmpty)
        let health = try await ProxmoxProvider(id: pve.id, displayName: pve.name, baseURL: pve.url, apiTokenValue: pve.credential).healthCheck()
        if case .ok = health {} else { Issue.record("health \(health)") }
    }

    @Test func detailScreensGetStatusAndCharts() async throws {
        let client = client()
        let status = try await client.guestStatus(node: "node-a", type: .qemu, vmid: 100)
        #expect(status.name == "service-01")
        for timeframe in ProxmoxRRDTimeframe.allCases {
            let points = try await client.guestRRD(node: "node-a", type: .qemu, vmid: 100, timeframe: timeframe)
            #expect(points.count > 10)
        }
        #expect(try await client.nodeStatus(node: "node-b").cpuCount == 8)
        #expect(try await client.nodeRRD(node: "node-a", timeframe: .day).count > 10)
    }

    @Test func simulatedActionChangesTheGuestState() async throws {
        let client = client()
        let upid = try await client.perform(.shutdown, node: "node-a", type: .qemu, vmid: 101)
        let result = try await client.waitForTask(node: "node-a", upid: upid, timeout: 5)
        #expect(result.succeeded)
        #expect(try await client.guestStatus(node: "node-a", type: .qemu, vmid: 101).status == "stopped")
        _ = try await client.perform(.start, node: "node-a", type: .qemu, vmid: 101)
        #expect(try await client.guestStatus(node: "node-a", type: .qemu, vmid: 101).status == "running")
    }

    @Test func backupServerLoads() async throws {
        let client = PBSClient(baseURL: pbs.url, apiTokenValue: pbs.credential,
                               httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil))
        let snapshot = try await PBSProvider.loadSnapshot(client: client, serviceID: pbs.id, serviceName: pbs.name)
        let inventory = PBSInventory(snapshots: [snapshot])
        #expect(inventory.datastores.count == 1)
        #expect(inventory.overview.guestsBackedUp >= 5)
        #expect(inventory.overview.staleBackups >= 1)
        #expect(!inventory.tasks.isEmpty)
        #expect(inventory.watchedConditions().allSatisfy { $0.kind == .backupFailed && $0.key.hasPrefix("pbs|") })
    }

    @Test func diskProblemsBecomeConditionsKeyedByLevel() {
        let id = UUID()
        let report = ProxmoxDiskHealth(nodes: [ProxmoxDiskHealth.Node(
            name: "node-a",
            disks: [ProxmoxDisk(devpath: "/dev/sda", health: .passed), ProxmoxDisk(devpath: "/dev/sdb", health: .failed)],
            pools: [ProxmoxZFSPool(name: "tank", health: "DEGRADED")]
        )])
        let conditions = report.watchedConditions(serviceID: id)
        #expect(conditions.allSatisfy { $0.scope == id.uuidString })
        #expect(conditions.map(\.key).sorted() == ["node-a/disk/dev/sdb|2", "node-a/pool/tank|1"])
        let worse = ProxmoxDiskHealth(nodes: [ProxmoxDiskHealth.Node(name: "node-a", disks: [], pools: [ProxmoxZFSPool(name: "tank", health: "FAULTED")])])
        #expect(worse.watchedConditions(serviceID: id).map(\.key) == ["node-a/pool/tank|2"])
    }
}
