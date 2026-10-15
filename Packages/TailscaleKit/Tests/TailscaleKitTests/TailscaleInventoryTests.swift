import Foundation
import Testing
import PatchNodeCore
@testable import TailscaleKit

private typealias F = TailscaleFixtures

@Suite("TailscaleDevice decoding")
struct TailscaleDeviceTests {
    private func device(_ json: String) throws -> TailscaleDevice {
        try JSONDecoder().decode(TailscaleDevice.self, from: Data(json.utf8))
    }

    @Test func decodesRealisticDeviceList() throws {
        let devices = try F.decodeDevices()
        // The entry without nodeId/id is dropped, not the whole list.
        #expect(devices.map(\.id) == ["nFakeNas1CNTRL", "nFakeLaptop1CNTRL", "nFakeOldPi1CNTRL", "nFakePhone1CNTRL", "nFakeNewServer1CNTRL"])

        let nas = devices[0]
        #expect(nas.name == "storage-node.example.invalid")
        #expect(nas.hostname == "storage-node")
        #expect(nas.shortName == "storage-node")
        #expect(nas.os == "linux")
        #expect(nas.addresses == ["192.0.2.1", "2001:db8::1"])
        #expect(nas.user == "owner@example.invalid")
        #expect(nas.clientVersion == "1.70.0-t1234567-gabcdef")
        #expect(nas.updateAvailable)
        #expect(nas.lastSeen == date(referenceEpoch - 2))
        #expect(nas.expires == date(referenceEpoch + 68 * 86400))
        #expect(nas.keyExpiry == nas.expires)
        #expect(nas.connectedToControl == true)
        #expect(nas.authorized)
    }

    @Test func zeroExpiryDateWithKeyExpiryDisabledIsNil() throws {
        let oldPi = try F.decodeDevices()[2]
        #expect(oldPi.keyExpiryDisabled)
        #expect(oldPi.expires == nil)
        #expect(oldPi.keyExpiry == nil)
        #expect(oldPi.connectedToControl == false)
    }

    @Test func keyExpiryIsIgnoredWhenDisabledEvenWithARealDate() throws {
        let device = try device(#"{"nodeId":"nFake1","name":"a.example.invalid","expires":"2024-05-02T10:00:00Z","keyExpiryDisabled":true}"#)
        #expect(device.expires != nil)
        #expect(device.keyExpiry == nil)
    }

    @Test func fractionalLastSeenIsParsed() throws {
        let phone = try F.decodeDevices()[3]
        let lastSeen = try #require(phone.lastSeen)
        #expect(abs(lastSeen.timeIntervalSince1970 - (referenceEpoch - 7200 + 0.123456789)) < 0.001)
    }

    @Test func connectedToControlAbsentIsNil() throws {
        #expect(try F.decodeDevices()[1].connectedToControl == nil)
    }

    @Test func unauthorizedFlagIsDecoded() throws {
        #expect(try F.decodeDevices()[4].authorized == false)
    }

    @Test func minimalDeviceUsesDefaults() throws {
        let device = try device(#"{"id":"1234567890"}"#)
        #expect(device.id == "1234567890")
        #expect(device.name == "1234567890")
        #expect(device.hostname == nil)
        #expect(device.addresses.isEmpty)
        #expect(device.authorized)
        #expect(!device.updateAvailable)
        #expect(!device.keyExpiryDisabled)
        #expect(device.lastSeen == nil)
        #expect(device.expires == nil)
    }

    @Test func nameFallsBackToHostnameAndShortNameToFirstLabel() throws {
        let noName = try device(#"{"nodeId":"nFake2","name":"","hostname":"backup-box"}"#)
        #expect(noName.name == "backup-box")
        let noHost = try device(#"{"nodeId":"nFake3","name":"media.example.invalid","hostname":""}"#)
        #expect(noHost.hostname == nil)
        #expect(noHost.shortName == "media")
    }

    @Test func missingIDFailsDecoding() {
        #expect(throws: DecodingError.self) { try device(#"{"name":"ghost.example.invalid"}"#) }
    }

    @Test func onlineUsesConnectedToControlThenLastSeenWindow() {
        let now = F.reference
        #expect(TailscaleDevice(id: "a", name: "a", lastSeen: date(referenceEpoch - 3 * 86400), connectedToControl: true).isOnline(now: now))
        #expect(!TailscaleDevice(id: "b", name: "b", lastSeen: now, connectedToControl: false).isOnline(now: now))
        #expect(TailscaleDevice(id: "c", name: "c", lastSeen: date(referenceEpoch - 60)).isOnline(now: now))
        #expect(!TailscaleDevice(id: "d", name: "d", lastSeen: date(referenceEpoch - 10 * 60)).isOnline(now: now))
        #expect(!TailscaleDevice(id: "e", name: "e").isOnline(now: now))
    }
}

@Suite("TailscaleInventory")
struct TailscaleInventoryTests {
    private func inventory(_ devices: [TailscaleDevice], now: Date = F.reference) -> TailscaleInventory {
        TailscaleInventory(snapshots: [TailscaleServiceSnapshot(serviceID: F.serviceID, serviceName: "Tailnet", devices: devices)], now: now)
    }

    private func item(_ inventory: TailscaleInventory, _ shortName: String) throws -> TailscaleInventory.Item {
        try #require(inventory.devices.first { $0.device.shortName == shortName })
    }

    @Test func issuesOfRealisticTailnet() throws {
        let inventory = inventory(try F.decodeDevices())
        #expect(try item(inventory, "storage-node").issues.isEmpty)
        #expect(try item(inventory, "device-a").issues == [.keyExpiringSoon(date(referenceEpoch + 9 * 86400))])
        #expect(try item(inventory, "device-b").issues == [.offline(since: date(referenceEpoch - 3 * 86400))])
        #expect(try item(inventory, "device-c").issues == [.keyExpired(date(referenceEpoch - 86400))])
        #expect(try item(inventory, "device-d").issues == [.notAuthorized])
    }

    @Test func offlineAlertOnlyAfter24Hours() throws {
        let recent = TailscaleDevice(id: "r", name: "recent", lastSeen: date(referenceEpoch - 23 * 3600), connectedToControl: false)
        let old = TailscaleDevice(id: "o", name: "old", lastSeen: date(referenceEpoch - 25 * 3600), connectedToControl: false)
        let never = TailscaleDevice(id: "n", name: "never", connectedToControl: false)
        let inventory = inventory([recent, old, never])
        #expect(try item(inventory, "recent").issues.isEmpty)
        #expect(try item(inventory, "old").issues == [.offline(since: date(referenceEpoch - 25 * 3600))])
        #expect(try item(inventory, "never").issues.isEmpty)
    }

    @Test func keyExpiryWarningWindowIs14Days() throws {
        let soon = TailscaleDevice(id: "s", name: "soon", expires: date(referenceEpoch + 13 * 86400), connectedToControl: true)
        let far = TailscaleDevice(id: "f", name: "far", expires: date(referenceEpoch + 15 * 86400), connectedToControl: true)
        let now = TailscaleDevice(id: "n", name: "now", expires: F.reference, connectedToControl: true)
        let disabled = TailscaleDevice(id: "d", name: "disabled", expires: date(referenceEpoch - 86400), keyExpiryDisabled: true, connectedToControl: true)
        let inventory = inventory([soon, far, now, disabled])
        #expect(try item(inventory, "soon").issues == [.keyExpiringSoon(date(referenceEpoch + 13 * 86400))])
        #expect(try item(inventory, "far").issues.isEmpty)
        #expect(try item(inventory, "now").issues == [.keyExpired(F.reference)])
        #expect(try item(inventory, "disabled").issues.isEmpty)
    }

    @Test func multipleIssuesOnOneDevice() throws {
        let device = TailscaleDevice(
            id: "x", name: "wreck", lastSeen: date(referenceEpoch - 5 * 86400), expires: date(referenceEpoch - 86400),
            connectedToControl: false, authorized: false
        )
        #expect(try item(inventory([device]), "wreck").issues == [
            .notAuthorized, .offline(since: date(referenceEpoch - 5 * 86400)), .keyExpired(date(referenceEpoch - 86400)),
        ])
    }

    @Test func sortsIssuesFirstThenOnlineThenName() throws {
        let inventory = inventory(try F.decodeDevices())
        #expect(inventory.devices.map(\.device.shortName) == ["device-a", "device-d", "device-b", "device-c", "storage-node"])
    }

    @Test func nameSortingIsNaturalAmongHealthyDevices() {
        let devices = ["node10", "Node2", "node1"].map { TailscaleDevice(id: $0, name: "\($0).example.invalid", connectedToControl: true) }
        let offline = TailscaleDevice(id: "z", name: "aaa-offline", lastSeen: date(referenceEpoch - 3600), connectedToControl: false)
        #expect(inventory(devices + [offline]).devices.map(\.device.shortName) == ["node1", "Node2", "node10", "aaa-offline"])
    }

    @Test func itemsKeepTheirServiceAndUniqueIDs() {
        let device = TailscaleDevice(id: "nSame", name: "same", connectedToControl: true)
        let inventory = TailscaleInventory(snapshots: [
            TailscaleServiceSnapshot(serviceID: F.serviceID, serviceName: "Home", devices: [device]),
            TailscaleServiceSnapshot(serviceID: F.otherServiceID, serviceName: "Work", devices: [device]),
        ], now: F.reference)
        #expect(Set(inventory.devices.map(\.id)).count == 2)
        #expect(Set(inventory.devices.map(\.serviceName)) == ["Home", "Work"])
        #expect(inventory.overview.total == 2)
    }

    @Test func overviewCountsRealisticTailnet() throws {
        let overview = inventory(try F.decodeDevices()).overview
        #expect(overview.total == 5)
        #expect(overview.online == 3)
        #expect(overview.offlineOver24h == 1)
        #expect(overview.keysExpiringSoon == 1)
        #expect(overview.keysExpired == 1)
    }

    @Test func emptyInventory() {
        let inventory = TailscaleInventory(snapshots: [], now: F.reference)
        #expect(inventory.devices.isEmpty)
        #expect(inventory.overview.total == 0)
        #expect(inventory.overview.level(failedServices: 0, totalServices: 0) == .ok)
    }

    // MARK: level

    @Test func levelIsCriticalWhenEveryServiceFailed() {
        let overview = inventory([]).overview
        #expect(overview.level(failedServices: 1, totalServices: 1) == .critical)
        #expect(overview.level(failedServices: 2, totalServices: 2) == .critical)
    }

    @Test func levelIsCriticalWhenAKeyExpired() {
        let expired = TailscaleDevice(id: "e", name: "e", expires: date(referenceEpoch - 60), connectedToControl: true)
        #expect(inventory([expired]).overview.level(failedServices: 0, totalServices: 1) == .critical)
    }

    @Test func levelIsWarningForPartialFailureOfflineOrExpiringKey() {
        let healthy = TailscaleDevice(id: "h", name: "h", connectedToControl: true)
        #expect(inventory([healthy]).overview.level(failedServices: 1, totalServices: 2) == .warning)

        let offline = TailscaleDevice(id: "o", name: "o", lastSeen: date(referenceEpoch - 2 * 86400), connectedToControl: false)
        #expect(inventory([offline]).overview.level(failedServices: 0, totalServices: 1) == .warning)

        let expiring = TailscaleDevice(id: "x", name: "x", expires: date(referenceEpoch + 86400), connectedToControl: true)
        #expect(inventory([expiring]).overview.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func levelIsOkForHealthyTailnetAndWarnsOnDeviceAwaitingApproval() {
        let healthy = TailscaleDevice(id: "h", name: "h", connectedToControl: true)
        #expect(inventory([healthy]).overview.level(failedServices: 0, totalServices: 1) == .ok)
        let pending = TailscaleDevice(id: "p", name: "p", connectedToControl: true, authorized: false)
        let overview = inventory([healthy, pending]).overview
        #expect(overview.awaitingApproval == 1)
        #expect(overview.level(failedServices: 0, totalServices: 1) == .warning)
    }
}
