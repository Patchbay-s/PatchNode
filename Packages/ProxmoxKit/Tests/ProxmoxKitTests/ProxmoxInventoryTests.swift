import Foundation
import Testing
import PatchNodeCore
@testable import ProxmoxKit

// MARK: - Builders

private let gib = 1_073_741_824
private let fixedNow = Date(timeIntervalSince1970: 1_719_930_000)

private func node(_ name: String, online: Bool = true, maxMemory: Int? = 32 * gib, maxCPU: Double? = 8) -> ProxmoxResource {
    ProxmoxResource(
        id: "node/\(name)", kind: .node, node: name, status: online ? "online" : "offline",
        maxCPU: maxCPU, maxMemory: maxMemory
    )
}

private func guest(
    _ type: ProxmoxGuestType, _ vmid: Int, on nodeName: String, running: Bool = true, template: Bool = false
) -> ProxmoxResource {
    ProxmoxResource(
        id: "\(type.rawValue)/\(vmid)", kind: .guest(type), node: nodeName, vmid: vmid,
        name: "\(type.rawValue)-\(vmid)", status: running ? "running" : "stopped", isTemplate: template
    )
}

private func storage(_ name: String, on nodeName: String, usage: Double, shared: Bool = false) -> ProxmoxResource {
    let total = 1_000_000_000_000
    return ProxmoxResource(
        id: "storage/\(nodeName)/\(name)", kind: .storage, node: nodeName, status: "available",
        disk: Int(Double(total) * usage), maxDisk: total, storage: name, isShared: shared
    )
}

private func task(
    _ suffix: String, node nodeName: String = "node-1", start: Date, status: String? = "OK", ended: Bool = true
) -> ProxmoxTask {
    ProxmoxTask(
        id: "UPID:\(nodeName):0000\(suffix):00C3D4E5:66840000:vzdump:100:root@pam:",
        node: nodeName, type: "vzdump", targetID: "100", user: "root@pam",
        startTime: start, endTime: ended ? start.addingTimeInterval(60) : nil, rawStatus: status
    )
}

private func snapshot(
    _ resources: [ProxmoxResource], tasks: [ProxmoxTask] = [], id: UUID = UUID(), name: String = "PVE"
) -> ProxmoxServiceSnapshot {
    ProxmoxServiceSnapshot(serviceID: id, serviceName: name, resources: resources, tasks: tasks, fetchedAt: fixedNow)
}

/// Same resources, as returned by any node of a two-node cluster.
private func clusterResources() -> [ProxmoxResource] {
    [
        node("node-1"), node("node-b"),
        guest(.qemu, 100, on: "node-1"), guest(.lxc, 200, on: "node-1"),
        guest(.qemu, 101, on: "node-b"), guest(.lxc, 201, on: "node-b", running: false),
        storage("local", on: "node-1", usage: 0.3), storage("local", on: "node-b", usage: 0.4),
    ]
}

// MARK: - Deduplication

@Suite("ProxmoxInventory deduplication")
struct ProxmoxInventoryDeduplicationTests {
    @Test func twoServicesOfSameClusterDoNotDuplicateNodesOrGuests() {
        let first = snapshot(clusterResources(), id: UUID(), name: "node-1")
        let second = snapshot(clusterResources(), id: UUID(), name: "node-b")
        let inventory = ProxmoxInventory(snapshots: [first, second], now: fixedNow)

        #expect(inventory.nodes.map(\.resource.node) == ["node-1", "node-b"])
        #expect(inventory.guests.count == 4)
        #expect(Set(inventory.guests.map(\.resource.id)).count == 4)
        #expect(inventory.storages.count == 2)
        #expect(inventory.overview.nodesTotal == 2)
        #expect(inventory.overview.vmsTotal == 2)
        #expect(inventory.overview.containersTotal == 2)
        // Everything is attributed to the first service that reported it.
        #expect(Set(inventory.guests.map(\.serviceID)) == [first.serviceID])
    }

    @Test func twoStandaloneHostsWithSameNameButDifferentHardwareAreBothKept() {
        let hostA = snapshot([node("node-1", maxMemory: 16 * gib), guest(.qemu, 100, on: "node-1")], name: "Home")
        let hostB = snapshot([node("node-1", maxMemory: 64 * gib), guest(.qemu, 100, on: "node-1")], name: "Office")
        let inventory = ProxmoxInventory(snapshots: [hostA, hostB], now: fixedNow)

        #expect(inventory.nodes.count == 2)
        #expect(Set(inventory.nodes.map(\.serviceID)) == [hostA.serviceID, hostB.serviceID])
        #expect(inventory.guests.count == 2)
        #expect(inventory.guests.allSatisfy { $0.resource.vmid == 100 })
        #expect(Set(inventory.guests.map(\.serviceID)) == [hostA.serviceID, hostB.serviceID])
        #expect(Set(inventory.guests.map(\.id)).count == 2)
        #expect(inventory.overview.nodesTotal == 2)
        #expect(inventory.overview.vmsTotal == 2)
    }

    @Test func tasksAreDedupedByUPIDWithinAServiceAndSortedNewestFirst() {
        let old = task("0001", start: fixedNow.addingTimeInterval(-7200))
        let recent = task("0002", start: fixedNow.addingTimeInterval(-60))
        let middle = task("0003", start: fixedNow.addingTimeInterval(-3600))
        let hostA = snapshot([node("node-1", maxMemory: 16 * gib)], tasks: [old, recent, old])
        let hostB = snapshot([node("node-1", maxMemory: 64 * gib)], tasks: [middle, recent])
        let inventory = ProxmoxInventory(snapshots: [hostA, hostB], now: fixedNow)

        // Two standalone hosts: a task of each is its own, even with the same UPID text.
        #expect(inventory.tasks.map(\.task.id) == [recent.id, recent.id, middle.id, old.id])
        #expect(Set(inventory.tasks.map(\.id)).count == 4)
        #expect(inventory.tasks.filter { $0.serviceID == hostA.serviceID }.map(\.task.id) == [recent.id, old.id])
    }

    @Test func tasksOfDuplicateClusterNodesAreNotRepeated() {
        let t = task("0001", start: fixedNow.addingTimeInterval(-60))
        let inventory = ProxmoxInventory(
            snapshots: [snapshot(clusterResources(), tasks: [t]), snapshot(clusterResources(), tasks: [t])],
            now: fixedNow
        )
        #expect(inventory.tasks.count == 1)
    }
}

// MARK: - Guests

@Suite("ProxmoxInventory guests")
struct ProxmoxInventoryGuestTests {
    @Test func templatesAreExcluded() {
        let inventory = ProxmoxInventory(snapshots: [snapshot([
            node("node-1"),
            guest(.qemu, 100, on: "node-1"),
            guest(.qemu, 9000, on: "node-1", running: false, template: true),
            guest(.lxc, 9001, on: "node-1", running: false, template: true),
        ])], now: fixedNow)
        #expect(inventory.guests.map(\.resource.vmid) == [100])
        #expect(inventory.overview.vmsTotal == 1)
        #expect(inventory.overview.containersTotal == 0)
    }

    @Test func guestsAreSortedByNodeThenVMID() {
        let inventory = ProxmoxInventory(snapshots: [snapshot([
            node("node-b"), node("node-1"),
            guest(.lxc, 300, on: "node-b"),
            guest(.qemu, 101, on: "node-1"),
            guest(.qemu, 102, on: "node-b"),
            guest(.lxc, 100, on: "node-1"),
        ])], now: fixedNow)
        let order = inventory.guests.map { "\($0.resource.node ?? "")/\($0.resource.vmid ?? 0)" }
        #expect(order == ["node-1/100", "node-1/101", "node-b/102", "node-b/300"])
        #expect(inventory.nodes.map(\.resource.node) == ["node-1", "node-b"])
    }
}

// MARK: - Overview

@Suite("ProxmoxInventory overview")
struct ProxmoxInventoryOverviewTests {
    @Test func countsNodesAndGuests() {
        let inventory = ProxmoxInventory(snapshots: [snapshot([
            node("node-1"), node("node-b"), node("node-c", online: false),
            guest(.qemu, 100, on: "node-1"), guest(.qemu, 101, on: "node-1", running: false), guest(.qemu, 102, on: "node-b"),
            guest(.lxc, 200, on: "node-1"), guest(.lxc, 201, on: "node-b", running: false),
        ])], now: fixedNow)
        let overview = inventory.overview
        #expect(overview.nodesOnline == 2)
        #expect(overview.nodesTotal == 3)
        #expect(overview.vmsRunning == 2)
        #expect(overview.vmsTotal == 3)
        #expect(overview.containersRunning == 1)
        #expect(overview.containersTotal == 2)
    }

    @Test func storageAt90PercentIsFlaggedAnd80PercentIsNot() {
        let inventory = ProxmoxInventory(snapshots: [snapshot([
            node("node-1"),
            storage("local", on: "node-1", usage: 0.80),
            storage("local-lvm", on: "node-1", usage: 0.90),
        ])], now: fixedNow)
        #expect(inventory.overview.storagesAboveThreshold.map(\.resource.storage) == ["local-lvm"])
    }

    @Test func sharedStorageAboveThresholdIsListedOnce() {
        let inventory = ProxmoxInventory(snapshots: [snapshot([
            node("node-1"), node("node-b"),
            storage("backup-nfs", on: "node-1", usage: 0.95, shared: true),
            storage("backup-nfs", on: "node-b", usage: 0.95, shared: true),
            storage("local-lvm", on: "node-1", usage: 0.92),
            storage("local-lvm", on: "node-b", usage: 0.91),
        ])], now: fixedNow)
        #expect(inventory.storages.count == 4)
        let flagged = inventory.overview.storagesAboveThreshold.map(\.resource.id)
        // Shared storage once; non-shared local storage of each node counted separately.
        #expect(flagged == ["storage/node-1/backup-nfs", "storage/node-1/local-lvm", "storage/node-b/local-lvm"])
    }

    @Test func recentFailedTasksCountsOnlyFailuresWithin24Hours() {
        let tasks = [
            task("0001", start: fixedNow.addingTimeInterval(-3600), status: "job errors"),
            task("0002", start: fixedNow.addingTimeInterval(-23 * 3600), status: "unable to open file"),
            task("0003", start: fixedNow.addingTimeInterval(-25 * 3600), status: "too old failure"),
            task("0004", start: fixedNow.addingTimeInterval(-600), status: "OK"),
            task("0005", start: fixedNow.addingTimeInterval(-600), status: "WARNINGS: 2"),
            task("0006", start: fixedNow.addingTimeInterval(-30), status: nil, ended: false),
        ]
        let inventory = ProxmoxInventory(snapshots: [snapshot([node("node-1")], tasks: tasks)], now: fixedNow)
        #expect(inventory.overview.recentFailedTasks == 2)
    }
}

// MARK: - Level

@Suite("ProxmoxOverview.level")
struct ProxmoxOverviewLevelTests {
    private func overview(_ resources: [ProxmoxResource], tasks: [ProxmoxTask] = []) -> ProxmoxOverview {
        ProxmoxInventory(snapshots: [snapshot(resources, tasks: tasks)], now: fixedNow).overview
    }

    private var healthy: [ProxmoxResource] {
        [node("node-1"), node("node-b"), guest(.qemu, 100, on: "node-1"), storage("local", on: "node-1", usage: 0.5)]
    }

    @Test func allServicesFailedIsCritical() {
        let empty = ProxmoxInventory(snapshots: [], now: fixedNow).overview
        #expect(empty.level(failedServices: 2, totalServices: 2) == .critical)
    }

    @Test func allNodesOfflineIsCritical() {
        let o = overview([node("node-1", online: false), node("node-b", online: false)])
        #expect(o.level(failedServices: 0, totalServices: 1) == .critical)
    }

    @Test func oneFailedServiceOutOfSeveralIsWarning() {
        #expect(overview(healthy).level(failedServices: 1, totalServices: 2) == .warning)
    }

    @Test func oneNodeOfflineIsWarning() {
        let o = overview([node("node-1"), node("node-b", online: false)])
        #expect(o.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func storageAlertIsWarning() {
        let o = overview(healthy + [storage("local-lvm", on: "node-1", usage: 0.9)])
        #expect(o.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func recentFailedTaskIsWarning() {
        let o = overview(healthy, tasks: [task("0001", start: fixedNow.addingTimeInterval(-600), status: "job errors")])
        #expect(o.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func healthyClusterIsOk() {
        let o = overview(healthy, tasks: [task("0001", start: fixedNow.addingTimeInterval(-600), status: "OK")])
        #expect(o.level(failedServices: 0, totalServices: 1) == .ok)
    }

    @Test func noServiceConfiguredIsOk() {
        let empty = ProxmoxInventory(snapshots: [], now: fixedNow).overview
        #expect(empty.level(failedServices: 0, totalServices: 0) == .ok)
    }
}
