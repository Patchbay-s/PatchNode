import Foundation
import Testing
@testable import ProxmoxKit

/// A guest gone while its node answers may be hidden by an ACL on /vms/<id>
/// (PVEAuditor replaced), not deleted: only reported, never assumed deleted.
@Suite("Guests no longer listed")
struct GuestsNoLongerListedTests {
    private static func node(_ name: String, online: Bool = true) -> ProxmoxResource {
        ProxmoxResource(id: "node/\(name)", kind: .node, node: name, status: online ? "online" : "offline")
    }

    private static func guest(_ vmid: Int, on node: String, type: ProxmoxGuestType = .lxc) -> ProxmoxResource {
        ProxmoxResource(id: "\(type.rawValue)/\(vmid)", kind: .guest(type), node: node, vmid: vmid, status: "running")
    }

    private static func snapshot(_ resources: [ProxmoxResource]) -> ProxmoxServiceSnapshot {
        ProxmoxServiceSnapshot(serviceID: UUID(), serviceName: "node-1", resources: resources)
    }

    @Test func aGuestGoneWhileItsNodeAnswersIsReported() {
        let before = Self.snapshot([Self.node("node-1"), Self.guest(101, on: "node-1"), Self.guest(102, on: "node-1", type: .qemu)])
        let after = Self.snapshot([Self.node("node-1"), Self.guest(102, on: "node-1", type: .qemu)])
        #expect(after.guestsNoLongerListed(since: before) == [101])
    }

    @Test func aGuestOfAnOfflineOrMissingNodeIsNot() {
        let before = Self.snapshot([Self.node("a"), Self.node("b"), Self.guest(101, on: "a"), Self.guest(201, on: "b")])
        let after = Self.snapshot([Self.node("a", online: false)])
        #expect(after.guestsNoLongerListed(since: before).isEmpty)
    }

    @Test func aMigratedGuestIsNot() {
        let before = Self.snapshot([Self.node("a"), Self.node("b"), Self.guest(101, on: "a")])
        let after = Self.snapshot([Self.node("a"), Self.node("b"), Self.guest(101, on: "b")])
        #expect(after.guestsNoLongerListed(since: before).isEmpty)
    }

    @Test func unchangedOrNewGuestsAreNot() {
        let before = Self.snapshot([Self.node("node-1"), Self.guest(101, on: "node-1")])
        let after = Self.snapshot([Self.node("node-1"), Self.guest(101, on: "node-1"), Self.guest(103, on: "node-1")])
        #expect(after.guestsNoLongerListed(since: before).isEmpty)
    }
}
