import Foundation
import Testing
import PatchNodeCore
@testable import ProxmoxKit

/// Phase 7: mapping of the Proxmox inventory to the snapshot shared with the
/// widgets and App Intents. Resources come from realistic `/cluster/resources`
/// responses read through `ProxmoxClient` with a simulated transport and a fake
/// token, so the "nothing secret in the file" check is meaningful.
private enum SharedFixtures {
    static let fakeToken = "test-user@pam!test-token=fake-only"
    static let homeURL = URL(string: "https://site-a-proxmox.example.invalid:8006")!
    static let officeURL = URL(string: "https://site-b-proxmox.example.invalid:8006")!

    static let homeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let officeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let soloID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let unnamedID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    static let gib = 1_073_741_824

    /// Two-node cluster: "node-1" online, "node-2" offline (with stale figures that must
    /// not be shown), a VM, a container and a VM template.
    static let homeResources = #"""
    {"data":[
      {"id":"node/node-1","type":"node","node":"node-1","status":"online","cpu":0.25,"maxcpu":8,
       "mem":8589934592,"maxmem":34359738368,"uptime":172800,"level":""},
      {"id":"node/node-2","type":"node","node":"node-2","status":"offline","cpu":0.9,"maxcpu":4,
       "mem":4294967296,"maxmem":17179869184},
      {"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"name":"test-app","status":"running",
       "cpu":0.02,"maxcpu":2,"mem":2147483648,"maxmem":4294967296,"template":0},
      {"id":"lxc/101","type":"lxc","node":"node-1","vmid":101,"name":"test-container","status":"stopped",
       "maxcpu":1,"maxmem":1073741824,"template":0},
      {"id":"qemu/9000","type":"qemu","node":"node-1","vmid":9000,"name":"test-vm-template",
       "status":"stopped","template":1},
      {"id":"storage/node-1/local","type":"storage","node":"node-1","storage":"local","status":"available",
       "disk":10737418240,"maxdisk":107374182400,"shared":0}
    ]}
    """#

    /// Standalone host whose node is also called "node-1", with the same VMID 100.
    static let officeResources = #"""
    {"data":[
      {"id":"node/node-1","type":"node","node":"node-1","status":"online","cpu":0.5,"maxcpu":8,
       "mem":17179869184,"maxmem":34359738368,"uptime":3600},
      {"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"name":"test-database","status":"running"},
      {"id":"lxc/9001","type":"lxc","node":"node-1","vmid":9001,"name":"test-container-template","status":"stopped","template":1}
    ]}
    """#

    /// Service named after its only node.
    static let soloResources = #"""
    {"data":[
      {"id":"node/node-c","type":"node","node":"node-c","status":"online","cpu":0.1,"maxcpu":4,
       "mem":1073741824,"maxmem":8589934592}
    ]}
    """#

    /// Service with an empty name.
    static let unnamedResources = #"""
    {"data":[
      {"id":"node/edge","type":"node","node":"edge","status":"online","cpu":0.05,"maxcpu":4,
       "mem":2147483648,"maxmem":8589934592}
    ]}
    """#
}

private typealias SF = SharedFixtures

private let now = Date(timeIntervalSince1970: 1_719_930_000)

private func snapshot(id: UUID, name: String, url: URL, json: String) async throws -> ProxmoxServiceSnapshot {
    let client = ProxmoxClient(baseURL: url, apiTokenValue: SF.fakeToken, httpClient: FakeHTTPClient.json(json))
    return ProxmoxServiceSnapshot(serviceID: id, serviceName: name, resources: try await client.clusterResources(), fetchedAt: now)
}

private func inventory() async throws -> ProxmoxInventory {
    ProxmoxInventory(snapshots: [
        try await snapshot(id: SF.homeID, name: "Site A", url: SF.homeURL, json: SF.homeResources),
        try await snapshot(id: SF.officeID, name: "Site B", url: SF.officeURL, json: SF.officeResources),
        try await snapshot(id: SF.soloID, name: "node-c", url: SF.homeURL, json: SF.soloResources),
        try await snapshot(id: SF.unnamedID, name: "", url: SF.homeURL, json: SF.unnamedResources),
    ], now: now)
}

private func tempStore() -> SharedSnapshotStore {
    let dir = FileManager.default.temporaryDirectory.appending(path: "PatchNode-proxmox-tests-\(UUID().uuidString)")
    return SharedSnapshotStore(fileURL: dir.appending(path: SharedSnapshotStore.fileName))
}

@Suite("Proxmox → shared snapshot: node loads")
struct ProxmoxSharedNodeLoadTests {
    @Test func homonymousNodesOfTwoServicesGetDistinctIDsAndServiceTitles() async throws {
        let loads = try await inventory().sharedNodeLoads()
        let sameNameNodes = loads.filter { $0.title.hasSuffix("· node-1") }
        #expect(sameNameNodes.count == 2)
        #expect(Set(sameNameNodes.map(\.id)).count == 2)
        #expect(Set(sameNameNodes.map(\.title)) == ["Site A · node-1", "Site B · node-1"])
        #expect(Set(loads.map(\.id)).count == loads.count)
        #expect(sameNameNodes.map(\.id).contains("\(SF.homeID.uuidString)|node/node-1"))
        #expect(sameNameNodes.map(\.id).contains("\(SF.officeID.uuidString)|node/node-1"))
    }

    @Test func titleIsTheNodeAloneWhenServiceNameIsEmptyOrEqualsTheNode() async throws {
        let loads = try await inventory().sharedNodeLoads()
        let solo = try #require(loads.first { $0.id == "\(SF.soloID.uuidString)|node/node-c" })
        let unnamed = try #require(loads.first { $0.id == "\(SF.unnamedID.uuidString)|node/edge" })
        #expect(solo.title == "node-c")
        #expect(unnamed.title == "edge")
    }

    @Test func onlineNodesComeFirstThenByTitle() async throws {
        let loads = try await inventory().sharedNodeLoads()
        #expect(loads.map(\.title) == ["edge", "node-c", "Site A · node-1", "Site B · node-1", "Site A · node-2"])
        #expect(loads.map(\.isOnline) == [true, true, true, true, false])
    }

    @Test func onlineNodesCarryCPUAndMemoryRatios() async throws {
        let loads = try await inventory().sharedNodeLoads()
        let home = try #require(loads.first { $0.title == "Site A · node-1" })
        #expect(home.cpu == 0.25)
        #expect(home.memory == 0.25)
        let office = try #require(loads.first { $0.title == "Site B · node-1" })
        #expect(office.cpu == 0.5)
        #expect(office.memory == 0.5)
    }

    @Test func offlineNodesHaveNoCPUOrMemory() async throws {
        let loads = try await inventory().sharedNodeLoads()
        let offline = try #require(loads.first { $0.title == "Site A · node-2" })
        #expect(!offline.isOnline)
        #expect(offline.cpu == nil)
        #expect(offline.memory == nil)
    }

    @Test func emptyInventoryHasNoNodeLoads() {
        let empty = ProxmoxInventory(snapshots: [], now: now)
        #expect(empty.sharedNodeLoads().isEmpty)
        #expect(empty.sharedGuestTargets().isEmpty)
    }
}

@Suite("Proxmox → shared snapshot: guest targets")
struct ProxmoxSharedGuestTargetTests {
    @Test func templatesAreNotTargets() async throws {
        let targets = try await inventory().sharedGuestTargets()
        #expect(targets.count == 3)
        #expect(!targets.contains { $0.vmid == 9000 || $0.vmid == 9001 })
        #expect(!targets.contains { $0.name.contains("template") })
    }

    @Test func targetIDIsTheActionTargetKey() async throws {
        let inv = try await inventory()
        let targets = inv.sharedGuestTargets()
        let keys = inv.guests.compactMap { ProxmoxActionTarget(item: $0)?.key }
        #expect(targets.map(\.id) == keys)
        #expect(Set(targets.map(\.id)).count == targets.count)
    }

    @Test func targetsKeepServiceNodeTypeVMIDAndName() async throws {
        let targets = try await inventory().sharedGuestTargets()
        let web = try #require(targets.first { $0.name == "test-app" })
        #expect(web.serviceID == SF.homeID)
        #expect(web.serviceName == "Site A")
        #expect(web.node == "node-1")
        #expect(web.type == "qemu")
        #expect(web.vmid == 100)
        let container = try #require(targets.first { $0.name == "test-container" })
        #expect(container.type == "lxc")
        #expect(container.vmid == 101)
        let db = try #require(targets.first { $0.name == "test-database" })
        #expect(db.serviceID == SF.officeID)
        #expect(db.serviceName == "Site B")
        #expect(db.vmid == 100)
        #expect(db.id != web.id)
    }

    @Test func sharedTargetRoundTripsToTheSameActionTarget() async throws {
        let inv = try await inventory()
        let targets = inv.sharedGuestTargets()
        let originals = inv.guests.compactMap { ProxmoxActionTarget(item: $0) }
        let rebuilt = targets.compactMap { ProxmoxActionTarget(shared: $0) }
        #expect(rebuilt == originals)
        #expect(zip(targets, rebuilt).allSatisfy { $0.id == $1.key })
    }

    @Test(arguments: ["node", "storage", "QEMU", ""])
    func invalidGuestTypeGivesNoActionTarget(_ type: String) {
        let shared = SharedSnapshot.GuestTarget(
            id: "x", serviceID: SF.homeID, serviceName: "Site A", node: "node-1", type: type, vmid: 100, name: "test-app"
        )
        #expect(ProxmoxActionTarget(shared: shared) == nil)
    }
}

@Suite("Proxmox → shared snapshot: store round trip")
struct ProxmoxSharedStoreTests {
    @Test func mappedSnapshotRoundTripsThroughTheStore() async throws {
        let inv = try await inventory()
        let snapshot = SharedSnapshot(generatedAt: now, nodes: inv.sharedNodeLoads(), guests: inv.sharedGuestTargets())
        let store = tempStore()
        defer { store.delete() }
        try store.write(snapshot)
        let read = try #require(store.read())
        #expect(read == snapshot)
        let rebuilt = read.guests.compactMap { ProxmoxActionTarget(shared: $0) }
        #expect(rebuilt == inv.guests.compactMap { ProxmoxActionTarget(item: $0) })
    }

    /// Widgets read this file, possibly on the lock screen: no URL, host or token.
    @Test func storedFileHoldsNoURLNorToken() async throws {
        let inv = try await inventory()
        let store = tempStore()
        defer { store.delete() }
        try store.write(SharedSnapshot(generatedAt: now, nodes: inv.sharedNodeLoads(), guests: inv.sharedGuestTargets()))
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.contains("https://"))
        // JSONEncoder escapes "/" by default.
        #expect(!text.contains(#"https:\/\/"#))
        #expect(!text.contains(SF.fakeToken))
        #expect(!text.contains("00000000-fake-0000-token"))
        #expect(!text.contains("example.invalid"))
        #expect(!text.contains("8006"))
    }
}
