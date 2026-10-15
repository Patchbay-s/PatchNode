import Foundation
import Testing
@testable import PatchNodeCore

struct ConfigurationExportTests {
    let pve = ConfigurationExport.Service(id: UUID(), kind: "proxmoxVE", name: "PVE", url: "https://proxmox.example.invalid:8006")
    let prom = ConfigurationExport.Service(id: UUID(), kind: "prometheus", name: "Prometheus", url: "https://prom.example.invalid")
    let ha = ConfigurationExport.Service(id: UUID(), kind: "homeAssistant", name: "Test Site A", url: "https://ha.example.invalid")
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func file(services: [ConfigurationExport.Service], favorites: [ConfigurationExport.Favorite] = [],
                      pins: [ConfigurationExport.Pin] = [], tabs: String? = nil, order: String? = nil) -> ConfigurationExport {
        ConfigurationExport(services: services, favorites: favorites, pins: pins, tabs: tabs, dashboardOrder: order, exportedAt: date)
    }

    // MARK: - File

    @Test func roundTripsAndContainsNoSecretField() throws {
        let favorite = ConfigurationExport.Favorite(id: UUID(), name: "CPU", query: "up", unit: "percent", rangeMinutes: 60, serviceID: prom.id, createdAt: date)
        let pin = ConfigurationExport.Pin(id: UUID(), serviceID: ha.id, entityID: "sensor.test_temperature", sortOrder: 0)
        let export = file(services: [pve, prom, ha], favorites: [favorite], pins: [pin], tabs: "dashboard,proxmox", order: "proxmox,docker")
        let data = try export.encoded()
        #expect(try ConfigurationExport.decode(data) == export)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in ["token", "secret", "password", "credential", "apikey"] {
            #expect(!text.contains(forbidden))
        }
        #expect(text.contains("\"format\":\"patchnode-configuration\""))
    }

    @Test func refusesForeignNewerHugeAndBrokenFiles() throws {
        #expect(throws: ConfigurationExport.ReadError.notPatchNode) {
            try ConfigurationExport.decode(Data(#"{"format":"other","version":1}"#.utf8))
        }
        #expect(throws: ConfigurationExport.ReadError.newerVersion(2)) {
            try ConfigurationExport.decode(Data(#"{"format":"PatchNode-configuration","version":2}"#.utf8))
        }
        #expect(throws: ConfigurationExport.ReadError.unreadable) {
            try ConfigurationExport.decode(Data("not json".utf8))
        }
        #expect(throws: ConfigurationExport.ReadError.unreadable) {
            try ConfigurationExport.decode(Data(#"{"format":"PatchNode-configuration","version":1,"services":"oops"}"#.utf8))
        }
        #expect(throws: ConfigurationExport.ReadError.tooLarge) {
            try ConfigurationExport.decode(Data(count: ConfigurationExport.maxFileSize + 1))
        }
    }

    @Test func fileNameAndQRCodeSize() throws {
        #expect(ConfigurationExport.fileName(at: date).hasPrefix("PatchNode-2026-"))
        #expect(ConfigurationExport.fileName(at: date).hasSuffix(".PatchNode.json"))
        let small = try file(services: [pve, prom, ha]).encoded()
        #expect(ConfigurationQRCode.fits(small))
        let many = (0..<40).map { ConfigurationExport.Service(id: UUID(), kind: "grafana", name: "Grafana \($0)", url: "https://g\($0).example.invalid") }
        #expect(!ConfigurationQRCode.fits(try file(services: many).encoded()))
    }

    // MARK: - Plan

    @Test func mergeAddsNewServicesAndSkipsDuplicatesByIDOrAddress() {
        let existing = file(services: [pve])
        let sameAddress = ConfigurationExport.Service(id: UUID(), kind: "proxmoxVE", name: "Other", url: "https://proxmox.example.invalid:8006/")
        let plan = ConfigurationImportPlan(file: file(services: [pve, sameAddress, prom]), existing: existing, mode: .merge)
        #expect(plan.servicesToAdd.map(\.id) == [prom.id])
        #expect(plan.servicesToRemove.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.duplicate, .duplicate])
    }

    @Test func invalidEntriesAreSkippedWithAReason() {
        let http = ConfigurationExport.Service(id: UUID(), kind: "grafana", name: "Plain", url: "http://g.example.invalid")
        let unknown = ConfigurationExport.Service(id: UUID(), kind: "kubernetes", name: "K8s", url: "https://k.example.invalid")
        let unnamed = ConfigurationExport.Service(id: UUID(), kind: "grafana", name: "   ", url: "https://g2.example.invalid")
        let withSecret = ConfigurationExport.Service(id: UUID(), kind: "grafana", name: "Creds", url: "https://user:pw@g3.example.invalid")
        let plan = ConfigurationImportPlan(file: file(services: [http, unknown, unnamed, withSecret]), existing: file(services: []), mode: .merge)
        #expect(plan.servicesToAdd.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.invalidURL, .unknownKind, .emptyName, .invalidURL])
        #expect(plan.isEmpty)
    }

    @Test func replaceRemovesEverythingCurrentAndTakesTabs() {
        let existing = file(services: [pve, prom], tabs: "dashboard,docker", order: "docker")
        let plan = ConfigurationImportPlan(file: file(services: [pve, ha], tabs: "dashboard,proxmox", order: "proxmox"), existing: existing, mode: .replace)
        #expect(Set(plan.servicesToRemove) == [pve.id, prom.id])
        #expect(plan.servicesToAdd.map(\.id) == [pve.id, ha.id])
        #expect(plan.tabs == "dashboard,proxmox")
        #expect(plan.dashboardOrder == "proxmox")
    }

    @Test func mergeKeepsTabsUnlessNoneWereSet() {
        let withTabs = ConfigurationImportPlan(file: file(services: [], tabs: "dashboard,proxmox"), existing: file(services: [], tabs: "dashboard"), mode: .merge)
        #expect(withTabs.tabs == nil)
        let without = ConfigurationImportPlan(file: file(services: [], tabs: "dashboard,proxmox"), existing: file(services: [], tabs: ""), mode: .merge)
        #expect(without.tabs == "dashboard,proxmox")
    }

    @Test func favoritesAndPinsFollowTheirServiceAndAreNotDuplicated() {
        let goodFavorite = ConfigurationExport.Favorite(id: UUID(), name: "CPU", query: "up", unit: "none", rangeMinutes: 60, serviceID: prom.id, createdAt: date)
        let sameQuery = ConfigurationExport.Favorite(id: UUID(), name: "Again", query: "up", unit: "none", rangeMinutes: 60, serviceID: prom.id, createdAt: date)
        let orphan = ConfigurationExport.Favorite(id: UUID(), name: "Orphan", query: "up", unit: "none", rangeMinutes: 60, serviceID: UUID(), createdAt: date)
        let wrongKind = ConfigurationExport.Favorite(id: UUID(), name: "PVE", query: "up", unit: "none", rangeMinutes: 60, serviceID: pve.id, createdAt: date)
        let goodPin = ConfigurationExport.Pin(id: UUID(), serviceID: ha.id, entityID: "light.test_light", sortOrder: 0)
        let badPin = ConfigurationExport.Pin(id: UUID(), serviceID: ha.id, entityID: "../../api", sortOrder: 1)
        let plan = ConfigurationImportPlan(
            file: file(services: [pve, prom, ha], favorites: [goodFavorite, sameQuery, orphan, wrongKind], pins: [goodPin, badPin]),
            existing: file(services: []), mode: .merge
        )
        #expect(plan.favoritesToAdd.map(\.id) == [goodFavorite.id])
        #expect(plan.pinsToAdd.map(\.id) == [goodPin.id])
    }

    @Test func favoritesOfAnAlreadyConfiguredServiceAreNotImportedTwice() {
        // The service exists already (merge skips it): its favorites stay as they are.
        let favorite = ConfigurationExport.Favorite(id: UUID(), name: "CPU", query: "up", unit: "none", rangeMinutes: 60, serviceID: prom.id, createdAt: date)
        let plan = ConfigurationImportPlan(file: file(services: [prom], favorites: [favorite]), existing: file(services: [prom], favorites: [favorite]), mode: .merge)
        #expect(plan.favoritesToAdd.isEmpty)
        #expect(plan.isEmpty)
    }

    @Test func serviceCountIsBounded() {
        let current = (0..<(ConfigurationExport.maxServices - 1)).map {
            ConfigurationExport.Service(id: UUID(), kind: "grafana", name: "G\($0)", url: "https://g\($0).example.invalid")
        }
        let plan = ConfigurationImportPlan(file: file(services: [pve, prom]), existing: file(services: current), mode: .merge)
        #expect(plan.servicesToAdd.count == 1)
        #expect(plan.skipped.map(\.reason) == [.tooMany])
    }

    @Test func demoServicesAreNeverImported() {
        let demoID = DemoCatalog.services[0]
        let byID = ConfigurationExport.Service(id: demoID.id, kind: demoID.kind.rawValue, name: "Demo", url: "https://real.example.invalid")
        let byHost = ConfigurationExport.Service(id: UUID(), kind: "grafana", name: "Fake", url: "https://grafana.\(DemoServer.domain)")
        let plan = ConfigurationImportPlan(file: file(services: [byID, byHost]), existing: file(services: []), mode: .merge)
        #expect(plan.servicesToAdd.isEmpty)
        #expect(plan.skipped.map(\.reason) == [.reserved, .reserved])
    }

    @Test func fixedAddressWinsOverTheFile() {
        let tailscale = ConfigurationExport.Service(id: UUID(), kind: "tailscale", name: "Tailnet", url: "https://evil.example.invalid")
        let plan = ConfigurationImportPlan(
            file: file(services: [tailscale]), existing: file(services: []), mode: .merge,
            fixedURL: { $0 == .tailscale ? URL(string: "https://api.tailscale.com") : nil }
        )
        #expect(plan.servicesToAdd.map(\.url) == ["https://api.tailscale.com"])
    }

    @Test func pinsAreRenumberedAfterTheExistingOnes() {
        let first = ConfigurationExport.Pin(id: UUID(), serviceID: ha.id, entityID: "light.a", sortOrder: Int.max)
        let second = ConfigurationExport.Pin(id: UUID(), serviceID: ha.id, entityID: "light.b", sortOrder: -5)
        let plan = ConfigurationImportPlan(file: file(services: [ha], pins: [first, second]), existing: file(services: []), mode: .merge)
        #expect(plan.pinsToAdd.map(\.entityID) == ["light.b", "light.a"])
        #expect(plan.pinsToAdd.map(\.sortOrder) == [0, 1])
    }

    @Test func favoritesAndSettingsAreBounded() {
        let wild = ConfigurationExport.Favorite(id: UUID(), name: String(repeating: "n", count: 500), query: "up", unit: "parsecs",
                                                rangeMinutes: -10, serviceID: prom.id, createdAt: date)
        let huge = String(repeating: "dashboard,", count: 200)
        let plan = ConfigurationImportPlan(file: file(services: [prom], favorites: [wild], tabs: huge, order: huge), existing: file(services: []), mode: .replace)
        let favorite = plan.favoritesToAdd.first
        #expect(favorite?.name.count == ConfigurationImportPlan.maxNameLength)
        #expect(favorite?.unit == "none")
        #expect(favorite?.rangeMinutes == 5)
        #expect(plan.tabs == nil)
        #expect(plan.dashboardOrder == nil)
    }
}
