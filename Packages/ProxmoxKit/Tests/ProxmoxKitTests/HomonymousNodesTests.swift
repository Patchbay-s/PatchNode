import Foundation
import Testing
import PatchNodeCore
@testable import ProxmoxKit

// BUGS.md CRITIQUE: two separate Proxmox services whose node is called "node-1".
// Nothing may be hidden or merged, every item keeps its service, and an action
// goes to the service the resource came from.

private let gib = 1_073_741_824
private let now = Date(timeIntervalSince1970: 1_719_930_000)

private func node(_ name: String, maxMemory: Int = 32 * gib, maxCPU: Double = 8) -> ProxmoxResource {
    ProxmoxResource(id: "node/\(name)", kind: .node, node: name, status: "online", maxCPU: maxCPU, maxMemory: maxMemory)
}

private func guest(_ type: ProxmoxGuestType, _ vmid: Int, on node: String, name: String) -> ProxmoxResource {
    ProxmoxResource(id: "\(type.rawValue)/\(vmid)", kind: .guest(type), node: node, vmid: vmid, name: name, status: "running")
}

private func storage(_ name: String, on node: String) -> ProxmoxResource {
    ProxmoxResource(id: "storage/\(node)/\(name)", kind: .storage, node: node, status: "available",
                    disk: 10, maxDisk: 100, storage: name)
}

private let homeID = UUID()
private let officeID = UUID()

/// Two standalone hosts, same node name, same hardware, same VMIDs.
private func twoHomonymousHosts() -> [ProxmoxServiceSnapshot] {
    [
        ProxmoxServiceSnapshot(serviceID: homeID, serviceName: "Test Site A", resources: [
            node("node-1"), guest(.qemu, 100, on: "node-1", name: "web"), guest(.lxc, 101, on: "node-1", name: "test-container"),
            storage("local", on: "node-1"),
        ], fetchedAt: now),
        ProxmoxServiceSnapshot(serviceID: officeID, serviceName: "Test Site B", resources: [
            node("node-1"), guest(.qemu, 100, on: "node-1", name: "db"), guest(.lxc, 101, on: "node-1", name: "test-service"),
            storage("local", on: "node-1"),
        ], fetchedAt: now),
    ]
}

@Suite("Homonymous nodes across services")
struct HomonymousNodesInventoryTests {
    @Test func nothingIsHiddenWhenHardwareAndVMIDsAreIdentical() {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        #expect(inventory.nodes.count == 2)
        #expect(inventory.guests.count == 4)
        #expect(inventory.storages.count == 2)
        #expect(inventory.duplicateServiceIDs.isEmpty)
        #expect(Set(inventory.guests.map(\.resource.name)) == ["web", "test-container", "db", "test-service"])
        #expect(inventory.overview.nodesTotal == 2)
        #expect(inventory.overview.vmsTotal == 2)
        #expect(inventory.overview.containersTotal == 2)
    }

    @Test func everyItemKeepsItsServiceAndHasAUniqueIdentity() throws {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        #expect(Set(inventory.nodes.map(\.id)).count == 2)
        #expect(Set(inventory.guests.map(\.id)).count == 4)
        #expect(Set(inventory.nodes.compactMap(\.nodeKey)).count == 2)
        let web = try #require(inventory.guests.first { $0.resource.name == "web" })
        let db = try #require(inventory.guests.first { $0.resource.name == "db" })
        #expect(web.serviceID == homeID)
        #expect(web.serviceName == "Test Site A")
        #expect(db.serviceID == officeID)
        #expect(db.serviceName == "Test Site B")
        #expect(web.id != db.id)
    }

    @Test func guestsOfANodeAreThoseOfItsService() {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        let home = inventory.guests(on: .init(serviceID: homeID, node: "node-1"))
        let office = inventory.guests(on: .init(serviceID: officeID, node: "node-1"))
        #expect(Set(home.compactMap(\.resource.name)) == ["web", "test-container"])
        #expect(Set(office.compactMap(\.resource.name)) == ["db", "test-service"])
    }

    @Test func twoDifferentClustersWithTheSameNodeNamesAreBothKept() {
        let a = ProxmoxServiceSnapshot(serviceID: homeID, serviceName: "A", resources: [
            node("node-1"), node("node-b"), guest(.qemu, 100, on: "node-1", name: "a1"),
        ], fetchedAt: now)
        let b = ProxmoxServiceSnapshot(serviceID: officeID, serviceName: "B", resources: [
            node("node-1", maxMemory: 64 * gib), node("node-b", maxMemory: 64 * gib), guest(.qemu, 200, on: "node-1", name: "b1"),
        ], fetchedAt: now)
        let inventory = ProxmoxInventory(snapshots: [a, b], now: now)
        #expect(inventory.nodes.count == 4)
        #expect(inventory.guests.count == 2)
        #expect(inventory.duplicateServiceIDs.isEmpty)
    }

    @Test func twoMembersOfOneClusterAreMergedAndReported() {
        let resources = [node("node-1"), node("node-b"), guest(.qemu, 100, on: "node-1", name: "x"), guest(.lxc, 101, on: "node-b", name: "y")]
        let a = ProxmoxServiceSnapshot(serviceID: homeID, serviceName: "A", resources: resources, fetchedAt: now)
        let b = ProxmoxServiceSnapshot(serviceID: officeID, serviceName: "B", resources: resources, fetchedAt: now)
        let inventory = ProxmoxInventory(snapshots: [a, b], now: now)
        #expect(inventory.nodes.count == 2)
        #expect(inventory.guests.count == 2)
        #expect(Set(inventory.guests.map(\.serviceID)) == [homeID])
        #expect(inventory.duplicateServiceIDs == [officeID])
    }

    /// A VM migrating between the two reads must not duplicate the whole cluster
    /// (two targets for one machine would bypass "one action at a time").
    @Test func clusterMembersAreMergedEvenWhileAVMMigrates() {
        let a = ProxmoxServiceSnapshot(serviceID: homeID, serviceName: "A", resources: [
            node("node-1"), node("node-b"), guest(.qemu, 100, on: "node-1", name: "moving"),
        ], fetchedAt: now)
        let b = ProxmoxServiceSnapshot(serviceID: officeID, serviceName: "B", resources: [
            node("node-1"), node("node-b"), guest(.qemu, 100, on: "node-b", name: "moving"),
        ], fetchedAt: now)
        let inventory = ProxmoxInventory(snapshots: [a, b], now: now)
        #expect(inventory.guests.count == 1)
        #expect(inventory.duplicateServiceIDs == [officeID])
    }

    @Test func tasksOfHomonymousNodesStayDistinct() {
        let upid = "UPID:pve:00001234:00C3D4E5:66840000:vzdump:100:root@pam:"
        let t = ProxmoxTask(id: upid, node: "node-1", type: "vzdump", targetID: "100", startTime: now, endTime: now, rawStatus: "OK")
        let snapshots = twoHomonymousHosts().map {
            ProxmoxServiceSnapshot(serviceID: $0.serviceID, serviceName: $0.serviceName, resources: $0.resources, tasks: [t], fetchedAt: now)
        }
        let inventory = ProxmoxInventory(snapshots: snapshots, now: now)
        #expect(inventory.tasks.count == 2)
        #expect(Set(inventory.tasks.map(\.id)).count == 2)
        #expect(Set(inventory.tasks.map(\.serviceID)) == [homeID, officeID])
    }
}

@Suite("Actions on homonymous nodes")
struct HomonymousNodesActionTests {
    private static let upid = "UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstop:100:test-user@pam!test-token:"

    private func clients() -> (home: FakeHTTPClient, office: FakeHTTPClient, lookup: @Sendable (UUID) async -> ProxmoxClient?) {
        let home = FakeHTTPClient.json(#"{"data":"\#(Self.upid)"}"#)
        let office = FakeHTTPClient.json(#"{"data":"\#(Self.upid)"}"#)
        let homeClient = ProxmoxClient(baseURL: URL(string: "https://home.example.invalid:8006")!, apiTokenValue: "site-a@pam!test-token=fake", httpClient: home)
        let officeClient = ProxmoxClient(baseURL: URL(string: "https://office.example.invalid:8006")!, apiTokenValue: "site-b@pam!test-token=fake", httpClient: office)
        return (home, office, { id in id == homeID ? homeClient : id == officeID ? officeClient : nil })
    }

    @Test(arguments: [ProxmoxGuestAction.start, .shutdown, .stop, .reboot])
    func actionGoesOnlyToTheServiceOfTheResource(_ action: ProxmoxGuestAction) async throws {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        let (home, office, lookup) = clients()

        let db = try #require(inventory.guests.first { $0.resource.name == "db" })
        let target = try #require(ProxmoxActionTarget(item: db))
        #expect(target.serviceID == officeID)
        let result = try await target.perform(action, clients: lookup)
        #expect(result?.upid == Self.upid)

        let officeSpecs = await office.receivedSpecs
        #expect(await home.receivedSpecs.isEmpty)
        #expect(officeSpecs.count == 1)
        #expect(officeSpecs.first?.method == .post)
        #expect(officeSpecs.first?.url.host == "office.example.invalid")
        #expect(officeSpecs.first?.url.path == "/api2/json/nodes/node-1/qemu/100/status/\(action.rawValue)")
        #expect(officeSpecs.first?.headers["Authorization"] == "PVEAPIToken=site-b@pam!test-token=fake")
    }

    @Test func containerOfTheFirstServiceGoesToTheFirstService() async throws {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        let (home, office, lookup) = clients()
        let sampleContainer = try #require(inventory.guests.first { $0.resource.name == "test-container" })
        _ = try await #require(ProxmoxActionTarget(item: sampleContainer)).perform(.reboot, clients: lookup)
        #expect(await office.receivedSpecs.isEmpty)
        #expect(await home.receivedSpecs.map(\.url.path) == ["/api2/json/nodes/node-1/lxc/101/status/reboot"])
    }

    @Test func targetsOfHomonymousGuestsHaveDistinctKeys() throws {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        let keys = inventory.guests.compactMap { ProxmoxActionTarget(item: $0)?.key }
        #expect(keys.count == 4)
        #expect(Set(keys).count == 4)
    }

    @Test func noClientForTheServiceSendsNothing() async throws {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        let (home, office, _) = clients()
        let web = try #require(inventory.guests.first { $0.resource.name == "web" })
        let result = try await #require(ProxmoxActionTarget(item: web)).perform(.stop) { _ in nil }
        #expect(result == nil)
        #expect(await home.receivedSpecs.isEmpty)
        #expect(await office.receivedSpecs.isEmpty)
    }

    @Test func nodeResourceIsNotAnActionTarget() throws {
        let inventory = ProxmoxInventory(snapshots: twoHomonymousHosts(), now: now)
        #expect(inventory.nodes.allSatisfy { ProxmoxActionTarget(item: $0) == nil })
    }
}
