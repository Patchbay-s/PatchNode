import Foundation
import Testing
import PatchNodeCore
@testable import ProxmoxKit

// MARK: - Builders

private let fixedNow = Date(timeIntervalSince1970: 1_719_930_000)
private let hour: TimeInterval = 3_600

private func group(_ type: PBSBackupGroup.BackupType, _ id: String, hoursAgo: Double?) -> PBSBackupGroup {
    PBSBackupGroup(type: type, backupID: id, lastBackup: hoursAgo.map { fixedNow.addingTimeInterval(-$0 * hour) })
}

private func store(_ name: String, usage: Double? = 0.5, groups: [PBSBackupGroup] = []) -> PBSDatastore {
    // Rounded per mille so that 0.85 gives exactly 850 / 1000.
    let total = 1_000
    let used = usage.map { Int(($0 * Double(total)).rounded()) }
    return PBSDatastore(
        name: name, total: usage == nil ? nil : total, used: used, available: used.map { total - $0 }, groups: groups
    )
}

private func task(_ suffix: String, type: String = "backup", hoursAgo: Double, status: String? = "OK", ended: Bool = true) -> ProxmoxTask {
    let start = fixedNow.addingTimeInterval(-hoursAgo * hour)
    return ProxmoxTask(
        id: "UPID:pbs:0000\(suffix):0003C4D5:00000000:66840000:\(type):backup-main:root@pam:",
        node: "pbs", type: type, targetID: "backup-main:vm/100", user: "root@pam",
        startTime: start, endTime: ended ? start.addingTimeInterval(120) : nil, rawStatus: status
    )
}

private func snapshot(
    _ stores: [PBSDatastore], tasks: [ProxmoxTask] = [], id: UUID = UUID(), name: String = "PBS"
) -> PBSServiceSnapshot {
    PBSServiceSnapshot(serviceID: id, serviceName: name, datastores: stores, tasks: tasks, fetchedAt: fixedNow)
}

private func inventory(_ snapshots: [PBSServiceSnapshot]) -> PBSInventory {
    PBSInventory(snapshots: snapshots, now: fixedNow)
}

// MARK: - Aggregation

@Suite("PBSInventory aggregation")
struct PBSInventoryAggregationTests {
    @Test func emptyInventoryHasNothing() {
        let inv = inventory([])
        #expect(inv.datastores.isEmpty)
        #expect(inv.tasks.isEmpty)
        #expect(inv.lastBackups.isEmpty)
        #expect(inv.overview.datastoresTotal == 0)
        #expect(inv.overview.latestBackup == nil)
        #expect(inv.overview.level(failedServices: 0, totalServices: 0) == .ok)
    }

    @Test func datastoresFromEveryServiceAreListedWithUniqueIDs() {
        let first = UUID(), second = UUID()
        let inv = inventory([
            snapshot([store("backup-main"), store("offsite")], id: first, name: "PBS home"),
            snapshot([store("backup-main")], id: second, name: "PBS remote"),
        ])
        #expect(inv.datastores.map(\.datastore.name) == ["backup-main", "offsite", "backup-main"])
        #expect(inv.datastores.map(\.serviceName) == ["PBS home", "PBS home", "PBS remote"])
        #expect(Set(inv.datastores.map(\.id)).count == 3)
        #expect(inv.overview.datastoresTotal == 3)
    }

    @Test func tasksFromEveryServiceAreSortedMostRecentFirst() {
        let inv = inventory([
            snapshot([], tasks: [task("1", hoursAgo: 5), task("2", hoursAgo: 1)], name: "A"),
            snapshot([], tasks: [task("3", hoursAgo: 3), ProxmoxTask(id: "UPID:pbs:nostart", type: "prune")], name: "B"),
        ])
        #expect(inv.tasks.count == 4)
        #expect(inv.tasks.prefix(3).map(\.serviceName) == ["A", "B", "A"])
        #expect(inv.tasks.prefix(3).map { $0.task.id.hasPrefix("UPID:pbs:00002") } == [true, false, false])
        #expect(inv.tasks.last?.task.startTime == nil)
    }

    @Test func sameUPIDOnTwoServicesKeepsDistinctIDs() {
        let shared = task("1", hoursAgo: 1)
        let inv = inventory([snapshot([], tasks: [shared]), snapshot([], tasks: [shared])])
        #expect(Set(inv.tasks.map(\.id)).count == 2)
    }
}

// MARK: - Latest backup per guest

@Suite("PBSInventory latest backup per guest")
struct PBSInventoryLastBackupTests {
    @Test func latestBackupWinsAcrossDatastoresAndServices() throws {
        let inv = inventory([
            snapshot([
                store("backup-main", groups: [group(.vm, "100", hoursAgo: 10)]),
                store("offsite", groups: [group(.vm, "100", hoursAgo: 30)]),
            ], name: "PBS home"),
            snapshot([
                store("remote-store", groups: [group(.vm, "100", hoursAgo: 2)]),
            ], name: "PBS remote"),
        ])
        #expect(inv.lastBackups.count == 1)
        let latest = try #require(inv.lastBackups.first)
        #expect(latest.id == "vm/100")
        #expect(latest.date == fixedNow.addingTimeInterval(-2 * hour))
        #expect(latest.datastore == "remote-store")
        #expect(latest.serviceName == "PBS remote")
    }

    @Test func olderBackupSeenLaterDoesNotReplaceNewerOne() throws {
        let inv = inventory([
            snapshot([store("fast", groups: [group(.ct, "200", hoursAgo: 1)])], name: "first"),
            snapshot([store("slow", groups: [group(.ct, "200", hoursAgo: 20)])], name: "second"),
        ])
        let latest = try #require(inv.lastBackups.first)
        #expect(latest.datastore == "fast")
        #expect(latest.serviceName == "first")
    }

    @Test func vmAndCtWithSameIDAreDistinctGuests() {
        let inv = inventory([snapshot([store("s", groups: [group(.vm, "100", hoursAgo: 1), group(.ct, "100", hoursAgo: 1)])])])
        #expect(Set(inv.lastBackups.map(\.id)) == ["vm/100", "ct/100"])
    }

    @Test func groupsWithoutLastBackupAreIgnored() {
        let inv = inventory([snapshot([store("s", groups: [group(.vm, "100", hoursAgo: nil), group(.vm, "101", hoursAgo: 3)])])])
        #expect(inv.lastBackups.map(\.id) == ["vm/101"])
        #expect(inv.overview.guestsBackedUp == 1)
    }

    @Test func lastBackupsAreSortedByTypeThenNumericID() {
        let inv = inventory([snapshot([store("s", groups: [
            group(.vm, "100", hoursAgo: 1),
            group(.vm, "9", hoursAgo: 1),
            group(.host, "nas", hoursAgo: 1),
            group(.ct, "1000", hoursAgo: 1),
            group(.ct, "200", hoursAgo: 1),
            group(.host, "backup-host", hoursAgo: 1),
        ])])])
        #expect(inv.lastBackups.map(\.id) == ["ct/200", "ct/1000", "host/backup-host", "host/nas", "vm/9", "vm/100"])
    }

    @Test func lastBackupLooksUpQemuAsVmAndLxcAsCt() throws {
        let inv = inventory([snapshot([store("backup-main", groups: [
            group(.vm, "100", hoursAgo: 4),
            group(.ct, "200", hoursAgo: 6),
        ])])])
        let vm = try #require(inv.lastBackup(vmid: 100, type: .qemu))
        #expect(vm.type == .vm)
        #expect(vm.date == fixedNow.addingTimeInterval(-4 * hour))
        let ct = try #require(inv.lastBackup(vmid: 200, type: .lxc))
        #expect(ct.type == .ct)
        #expect(ct.datastore == "backup-main")
    }

    @Test func lastBackupReturnsNilForWrongTypeOrUnknownGuest() {
        let inv = inventory([snapshot([store("s", groups: [group(.vm, "100", hoursAgo: 4)])])])
        #expect(inv.lastBackup(vmid: 100, type: .lxc) == nil)
        #expect(inv.lastBackup(vmid: 101, type: .qemu) == nil)
    }

    @Test func latestBackupDateIsTheMostRecentOverall() {
        let inv = inventory([snapshot([store("s", groups: [group(.vm, "100", hoursAgo: 4), group(.host, "nas", hoursAgo: 0.5)])])])
        #expect(inv.overview.latestBackup == fixedNow.addingTimeInterval(-0.5 * hour))
    }
}

// MARK: - Overview

@Suite("PBSOverview counters")
struct PBSOverviewCounterTests {
    @Test func backupOlderThan48HoursIsStale() {
        let inv = inventory([snapshot([store("s", groups: [
            group(.vm, "100", hoursAgo: 49),
            group(.ct, "200", hoursAgo: 72),
            group(.vm, "101", hoursAgo: 47),
        ])])])
        #expect(inv.overview.staleBackups == 2)
    }

    @Test func backupExactly48HoursOldIsNotStale() {
        let inv = inventory([snapshot([store("s", groups: [group(.vm, "100", hoursAgo: 48)])])])
        #expect(inv.overview.staleBackups == 0)
    }

    @Test func staleHostBackupIsNotCounted() {
        let inv = inventory([snapshot([store("s", groups: [group(.host, "nas", hoursAgo: 500)])])])
        #expect(inv.overview.staleBackups == 0)
        #expect(inv.overview.guestsBackedUp == 1)
    }

    @Test func guestIsNotStaleWhenAnotherStoreHasARecentBackup() {
        let inv = inventory([snapshot([
            store("backup-main", groups: [group(.vm, "100", hoursAgo: 100)]),
            store("offsite", groups: [group(.vm, "100", hoursAgo: 12)]),
        ])])
        #expect(inv.overview.staleBackups == 0)
    }

    @Test func failedTasksCountOnlyWithin24Hours() {
        let inv = inventory([snapshot([], tasks: [
            task("1", type: "garbage_collection", hoursAgo: 2, status: "TASK ERROR: unable to access chunk store"),
            task("2", type: "backup", hoursAgo: 23.9, status: "backup failed: connection reset"),
            task("3", type: "verificationjob", hoursAgo: 30, status: "verification failed"),
            task("4", type: "backup", hoursAgo: 1, status: "WARNINGS: 2"),
            task("5", type: "backup", hoursAgo: 0.1, status: nil, ended: false),
            task("6", type: "backup", hoursAgo: 3),
        ])])
        #expect(inv.overview.failedTasks24h == 2)
    }

    @Test func failedTasksAreSummedAcrossServices() {
        let inv = inventory([
            snapshot([], tasks: [task("1", hoursAgo: 1, status: "TASK ERROR: x")]),
            snapshot([], tasks: [task("2", hoursAgo: 2, status: "TASK ERROR: y")]),
        ])
        #expect(inv.overview.failedTasks24h == 2)
    }

    @Test func succeededBackupsCountOnlyOkBackupTasksWithin24Hours() {
        let inv = inventory([snapshot([], tasks: [
            task("1", type: "backup", hoursAgo: 1),
            task("2", type: "backup", hoursAgo: 5),
            task("3", type: "backup", hoursAgo: 30),
            task("4", type: "prune", hoursAgo: 1),
            task("5", type: "backup", hoursAgo: 2, status: "TASK ERROR: x"),
            task("6", type: "backup", hoursAgo: 2, status: "WARNINGS: 1"),
        ])])
        #expect(inv.overview.succeededBackups24h == 2)
    }

    @Test func datastoreAtOrAbove85PercentIsFlagged() {
        let inv = inventory([snapshot([
            store("full", usage: 0.95),
            store("edge", usage: 0.85),
            store("below", usage: 0.849),
            store("unknown", usage: nil),
        ])])
        #expect(inv.overview.datastoresAboveThreshold == 2)
        #expect(inv.overview.datastoresTotal == 4)
    }
}

// MARK: - Level

@Suite("PBSOverview.level")
struct PBSOverviewLevelTests {
    private let healthy = inventory([snapshot(
        [store("s", usage: 0.4, groups: [group(.vm, "100", hoursAgo: 3)])],
        tasks: [task("1", hoursAgo: 3)]
    )]).overview

    @Test func healthyServerIsOk() {
        #expect(healthy.level(failedServices: 0, totalServices: 1) == .ok)
    }

    @Test func everyServiceFailedIsCritical() {
        #expect(healthy.level(failedServices: 1, totalServices: 1) == .critical)
        #expect(healthy.level(failedServices: 2, totalServices: 2) == .critical)
    }

    @Test func noConfiguredServiceIsNotCritical() {
        #expect(healthy.level(failedServices: 0, totalServices: 0) == .ok)
    }

    @Test func someServicesFailedIsWarning() {
        #expect(healthy.level(failedServices: 1, totalServices: 2) == .warning)
    }

    @Test func failedTaskIsWarning() {
        let overview = inventory([snapshot([store("s", usage: 0.4)], tasks: [task("1", hoursAgo: 1, status: "TASK ERROR: x")])]).overview
        #expect(overview.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func fullDatastoreIsWarning() {
        let overview = inventory([snapshot([store("s", usage: 0.9)])]).overview
        #expect(overview.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func staleBackupIsWarning() {
        let overview = inventory([snapshot([store("s", usage: 0.4, groups: [group(.ct, "200", hoursAgo: 60)])])]).overview
        #expect(overview.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func allFailedStaysCriticalEvenWithOtherWarnings() {
        let overview = inventory([snapshot([store("s", usage: 0.99)])]).overview
        #expect(overview.level(failedServices: 1, totalServices: 1) == .critical)
    }
}
