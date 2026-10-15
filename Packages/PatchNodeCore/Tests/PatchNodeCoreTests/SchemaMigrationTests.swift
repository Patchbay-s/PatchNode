#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import PatchNodeCore

/// Simulates an update: a store written the way PatchNode 1.0 wrote it (unversioned
/// schema, the frozen V1 classes), then opened by the current version (schema V2 +
/// migration plan, lightweight stage V1 → V2). The configured services must all
/// come back. Runs on macOS (`swift test`), not on Linux where SwiftData doesn't exist.
struct SchemaMigrationTests {
    private let proxmoxID = UUID()
    private let prometheusID = UUID()
    private let homeID = UUID()
    private let favoriteID = UUID()
    private let pinID = UUID()
    private let createdAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PatchNode-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "default.store")
    }

    /// Writes services, a pin and a synced setting exactly like 1.1 did.
    private func writeVersion11Store(at url: URL) throws {
        typealias V2 = PatchNodeSchemaV2
        let schema = Schema(versionedSchema: V2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        context.insert(V2.ServiceConfig(id: proxmoxID, kindRawValue: "proxmoxVE", name: "Proxmox test", urlString: "https://proxmox.example.invalid:8006"))
        context.insert(V2.ServiceConfig(id: prometheusID, kindRawValue: "prometheus", name: "Prometheus", urlString: "https://prom.example.invalid"))
        context.insert(V2.ServiceConfig(id: homeID, kindRawValue: "homeAssistant", name: "Home Assistant test", urlString: "https://ha.example.invalid"))
        context.insert(V2.PromQLFavorite(id: favoriteID, name: "CPU", query: "avg(rate(node_cpu_seconds_total[5m]))", unitRawValue: "percent",
                                         rangeMinutes: 360, serviceID: prometheusID, createdAt: createdAt))
        context.insert(V2.HomeAssistantPin(id: pinID, serviceID: homeID, entityID: "sensor.test_temperature", sortOrder: 2))
        context.insert(V2.SyncedSetting(key: "tabSelection", value: "dashboard,docker", updatedAt: createdAt))
        try context.save()
    }

    @Test func updateFromVersion11KeepsEverythingAndAddsSSHHosts() throws {
        let url = try makeStoreURL()
        try writeVersion11Store(at: url)
        let context = try openCurrent(at: url)
        try expectEverythingKept(in: context)
        #expect(try context.fetch(FetchDescriptor<SyncedSetting>()).map(\.value) == ["dashboard,docker"])
        #expect(try context.fetchCount(FetchDescriptor<SSHHost>()) == 0)
        let host = SSHHost(name: "nas", hostname: "nas.example.invalid", username: "admin", link: .dockerHost, linkedServiceID: proxmoxID, linkedTarget: "local")
        context.insert(host)
        try context.save()
        let reopened = try openCurrent(at: url)
        let saved = try #require(try reopened.fetch(FetchDescriptor<SSHHost>()).first)
        #expect(saved.port == 22)
        #expect(saved.link == .dockerHost)
        #expect(saved.pinnedHostKey.isEmpty)
    }

    /// Writes services, a favorite and a pin exactly like 1.0 did.
    private func writeVersion10Store(at url: URL) throws {
        typealias V1 = PatchNodeSchemaV1
        let schema = Schema([V1.ServiceConfig.self, V1.PromQLFavorite.self, V1.HomeAssistantPin.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        context.insert(V1.ServiceConfig(id: proxmoxID, kindRawValue: "proxmoxVE", name: "Proxmox test", urlString: "https://proxmox.example.invalid:8006"))
        context.insert(V1.ServiceConfig(id: prometheusID, kindRawValue: "prometheus", name: "Prometheus", urlString: "https://prom.example.invalid"))
        context.insert(V1.ServiceConfig(id: homeID, kindRawValue: "homeAssistant", name: "Home Assistant test", urlString: "https://ha.example.invalid"))
        context.insert(V1.PromQLFavorite(id: favoriteID, name: "CPU", query: "avg(rate(node_cpu_seconds_total[5m]))", unitRawValue: "percent",
                                         rangeMinutes: 360, serviceID: prometheusID, createdAt: createdAt))
        context.insert(V1.HomeAssistantPin(id: pinID, serviceID: homeID, entityID: "sensor.test_temperature", sortOrder: 2))
        try context.save()
    }

    private func openCurrent(at url: URL) throws -> ModelContext {
        let configuration = ModelConfiguration(schema: PatchNodeModelStore.schema, url: url)
        return ModelContext(try PatchNodeModelStore.makeContainer(configuration: configuration))
    }

    private func expectEverythingKept(in context: ModelContext) throws {
        // By ID: a name sort is localized ("Prometheus" before "PVE" on Apple platforms).
        let services = try context.fetch(FetchDescriptor<ServiceConfig>())
        let byID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        #expect(services.count == 3)
        #expect(byID[homeID]?.kind == .homeAssistant)
        #expect(byID[homeID]?.urlString == "https://ha.example.invalid")
        #expect(byID[proxmoxID]?.kind == .proxmoxVE)
        #expect(byID[proxmoxID]?.urlString == "https://proxmox.example.invalid:8006")
        #expect(byID[prometheusID]?.kind == .prometheus)
        #expect(byID[prometheusID]?.urlString == "https://prom.example.invalid")

        let favorite = try #require(try context.fetch(FetchDescriptor<PromQLFavorite>()).first)
        #expect(favorite.id == favoriteID)
        #expect(favorite.query == "avg(rate(node_cpu_seconds_total[5m]))")
        #expect(favorite.unit == .percent)
        #expect(favorite.rangeMinutes == 360)
        #expect(favorite.serviceID == prometheusID)
        #expect(favorite.createdAt == createdAt)

        let pin = try #require(try context.fetch(FetchDescriptor<HomeAssistantPin>()).first)
        #expect(pin.id == pinID)
        #expect(pin.serviceID == homeID)
        #expect(pin.entityID == "sensor.test_temperature")
        #expect(pin.sortOrder == 2)
    }

    @Test func updateFromVersion10KeepsEveryService() throws {
        let url = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeVersion10Store(at: url)

        try expectEverythingKept(in: try openCurrent(at: url))
    }

    @Test func storeStillOpensAfterSeveralLaunches() throws {
        let url = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeVersion10Store(at: url)

        // First launch of the update adds a service; the next launches keep it all.
        do {
            let context = try openCurrent(at: url)
            context.insert(ServiceConfig(kind: .grafana, name: "Grafana", urlString: "https://grafana.example.invalid"))
            try context.save()
        }
        for _ in 0..<2 {
            let context = try openCurrent(at: url)
            #expect(try context.fetchCount(FetchDescriptor<ServiceConfig>()) == 4)
        }
    }

    @Test func migratedStoreTakesSyncedSettings() throws {
        let url = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try writeVersion10Store(at: url)
        do {
            let context = try openCurrent(at: url)
            context.insert(SyncedSetting(key: "tabSelection", value: "dashboard,proxmox", updatedAt: createdAt))
            try context.save()
        }
        let context = try openCurrent(at: url)
        #expect(try context.fetch(FetchDescriptor<SyncedSetting>()).map(\.value) == ["dashboard,proxmox"])
        try expectEverythingKept(in: context)
    }

    /// Without the unique constraint, two copies of a service can exist after a
    /// sync: deleting through the helpers removes them all.
    @Test func duplicatesAreToleratedAndDeletedTogether() throws {
        let url = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = try openCurrent(at: url)
        let id = UUID()
        context.insert(ServiceConfig(id: id, kind: .grafana, name: "Grafana", urlString: "https://g.example.invalid"))
        context.insert(ServiceConfig(id: id, kind: .grafana, name: "Grafana", urlString: "https://g.example.invalid"))
        context.insert(PromQLFavorite(id: favoriteID, name: "CPU", query: "up", unit: .none, rangeMinutes: 60, serviceID: prometheusID))
        context.insert(PromQLFavorite(id: favoriteID, name: "CPU", query: "up", unit: .none, rangeMinutes: 60, serviceID: prometheusID))
        context.insert(HomeAssistantPin(serviceID: homeID, entityID: "light.test_light", sortOrder: 0))
        context.insert(HomeAssistantPin(serviceID: homeID, entityID: "light.test_light", sortOrder: 1))
        try context.save()
        #expect(try context.serviceRecords(id: id).count == 2)
        #expect(try context.fetch(FetchDescriptor<ServiceConfig>()).uniqued(by: \.id).count == 1)
        try context.deleteFavorite(id: favoriteID)
        try context.deletePin(serviceID: homeID, entityID: "light.test_light")
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PromQLFavorite>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HomeAssistantPin>()) == 0)
    }

    @Test func settingsReconcileThroughTheStore() throws {
        let url = try makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = try openCurrent(at: url)
        let defaults = try #require(UserDefaults(suiteName: "PatchNode-sync-\(UUID().uuidString)"))
        defaults.set("dashboard,docker", forKey: "tabSelection")
        // Nothing synced yet: this device publishes its tabs.
        try CloudHousekeeping.reconcileSettings(in: context, defaults: defaults, now: createdAt)
        #expect(try context.fetch(FetchDescriptor<SyncedSetting>()).map(\.value) == ["dashboard,docker"])
        // Another device's newer value arrives: adopted, the older record goes.
        context.insert(SyncedSetting(key: "tabSelection", value: "dashboard,proxmox", updatedAt: createdAt + 60))
        try context.save()
        try CloudHousekeeping.reconcileSettings(in: context, defaults: defaults, now: createdAt + 120)
        #expect(defaults.string(forKey: "tabSelection") == "dashboard,proxmox")
        #expect(try context.fetch(FetchDescriptor<SyncedSetting>()).map(\.value) == ["dashboard,proxmox"])
    }

    @Test func planEndsOnTheCurrentSchema() {
        #expect(PatchNodeMigrationPlan.schemas.map { ObjectIdentifier($0) }
            == [ObjectIdentifier(PatchNodeSchemaV1.self), ObjectIdentifier(PatchNodeSchemaV2.self), ObjectIdentifier(PatchNodeSchemaV3.self)])
        #expect(PatchNodeMigrationPlan.stages.count == PatchNodeMigrationPlan.schemas.count - 1)
        #expect(PatchNodeSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(PatchNodeSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(PatchNodeSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    }

    private func fingerprint(_ schema: Schema) -> [String] {
        schema.entities
            .flatMap { entity in
                entity.attributes.map { attribute in
                    "\(entity.name).\(attribute.name):\(attribute.valueType)\(attribute.isOptional ? "?" : "")\(attribute.isUnique ? " unique" : "")"
                }
            }
            .sorted()
    }

    /// The shape of the 1.0 store: the frozen V1 classes must never change.
    @Test func frozenV1StillMatchesVersion10() {
        #expect(fingerprint(Schema(versionedSchema: PatchNodeSchemaV1.self)) == [
            "HomeAssistantPin.entityID:String",
            "HomeAssistantPin.id:UUID unique",
            "HomeAssistantPin.serviceID:UUID",
            "HomeAssistantPin.sortOrder:Int",
            "PromQLFavorite.createdAt:Date",
            "PromQLFavorite.id:UUID unique",
            "PromQLFavorite.name:String",
            "PromQLFavorite.query:String",
            "PromQLFavorite.rangeMinutes:Int",
            "PromQLFavorite.serviceID:UUID",
            "PromQLFavorite.unitRawValue:String",
            "ServiceConfig.id:UUID unique",
            "ServiceConfig.kindRawValue:String",
            "ServiceConfig.name:String",
            "ServiceConfig.urlString:String",
        ])
    }

    /// The shape of the 1.1 store: the frozen V2 classes must never change.
    @Test func frozenV2StillMatchesVersion11() {
        #expect(fingerprint(Schema(versionedSchema: PatchNodeSchemaV2.self)) == [
            "HomeAssistantPin.entityID:String",
            "HomeAssistantPin.id:UUID",
            "HomeAssistantPin.serviceID:UUID",
            "HomeAssistantPin.sortOrder:Int",
            "PromQLFavorite.createdAt:Date",
            "PromQLFavorite.id:UUID",
            "PromQLFavorite.name:String",
            "PromQLFavorite.query:String",
            "PromQLFavorite.rangeMinutes:Int",
            "PromQLFavorite.serviceID:UUID",
            "PromQLFavorite.unitRawValue:String",
            "ServiceConfig.id:UUID",
            "ServiceConfig.kindRawValue:String",
            "ServiceConfig.name:String",
            "ServiceConfig.urlString:String",
            "SyncedSetting.key:String",
            "SyncedSetting.updatedAt:Date",
            "SyncedSetting.value:String",
        ])
    }

    /// The shape of the current schema. If this fails, a model changed: freeze V3
    /// and add a V4 with a migration stage (see `PatchNodeSchemaV3`), then update
    /// this list.
    @Test func currentModelsMatchV3() {
        #expect(fingerprint(PatchNodeModelStore.schema) == [
            "HomeAssistantPin.entityID:String",
            "HomeAssistantPin.id:UUID",
            "HomeAssistantPin.serviceID:UUID",
            "HomeAssistantPin.sortOrder:Int",
            "PromQLFavorite.createdAt:Date",
            "PromQLFavorite.id:UUID",
            "PromQLFavorite.name:String",
            "PromQLFavorite.query:String",
            "PromQLFavorite.rangeMinutes:Int",
            "PromQLFavorite.serviceID:UUID",
            "PromQLFavorite.unitRawValue:String",
            "SSHHost.createdAt:Date",
            "SSHHost.hostname:String",
            "SSHHost.id:UUID",
            "SSHHost.linkRawValue:String",
            "SSHHost.linkedServiceID:Optional<UUID>?",
            "SSHHost.linkedTarget:String",
            "SSHHost.name:String",
            "SSHHost.pinnedHostKey:String",
            "SSHHost.port:Int",
            "SSHHost.username:String",
            "ServiceConfig.id:UUID",
            "ServiceConfig.kindRawValue:String",
            "ServiceConfig.name:String",
            "ServiceConfig.urlString:String",
            "SyncedSetting.key:String",
            "SyncedSetting.updatedAt:Date",
            "SyncedSetting.value:String",
        ])
    }

    /// What CloudKit requires of a synced schema: no unique attribute, every
    /// attribute optional or with a default value.
    @Test func currentSchemaIsCloudKitCompatible() {
        for entity in PatchNodeModelStore.schema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name)")
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name) needs a default")
            }
        }
    }
}
#endif
