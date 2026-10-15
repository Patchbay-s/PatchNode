import Foundation
import Testing
import PatchNodeCore
@testable import HomeServicesKit

@Suite("HomeServicesInventory")
struct HomeServicesInventoryTests {
    private static let haID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private static let ha2ID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private static let nasID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let piID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let emptyGlancesID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private static let healthy = GlancesSummary(
        hostname: "nas", cpuPercent: 10, memoryPercent: 40,
        fileSystems: [.init(mountPoint: "/", percent: 40)]
    )
    private static let stressed = GlancesSummary(
        apiVersion: 3, hostname: "pi", cpuPercent: 80, memoryPercent: 90,
        fileSystems: [.init(mountPoint: "/", percent: 85), .init(mountPoint: "/data", percent: 97), .init(mountPoint: "/boot", percent: 10)]
    )

    private static let entities = [
        HAEntity(id: "sensor.living_room_temperature", name: "Living room temperature", state: "21.5", unit: "°C"),
        HAEntity(id: "scene.movie_night", name: "Movie night", state: "x"),
    ]

    private static func snapshots(nasSummary: GlancesSummary = healthy, piSummary: GlancesSummary? = nil) -> [HomeServiceSnapshot] {
        var result = [
            HomeServiceSnapshot(serviceID: haID, serviceName: "Home", kind: .homeAssistant, entities: entities),
            HomeServiceSnapshot(serviceID: nasID, serviceName: "NAS", kind: .glances, glances: nasSummary),
            HomeServiceSnapshot(serviceID: emptyGlancesID, serviceName: "Broken", kind: .glances, glances: nil),
            HomeServiceSnapshot(serviceID: ha2ID, serviceName: "Cabin", kind: .homeAssistant),
            HomeServiceSnapshot(serviceID: UUID(), serviceName: "Other", kind: .grafana, entities: entities),
        ]
        if let piSummary {
            result.append(HomeServiceSnapshot(serviceID: piID, serviceName: "Pi", kind: .glances, glances: piSummary))
        }
        return result
    }

    @Test func splitsSnapshotsByKindAndSkipsGlancesWithoutSummary() {
        let inventory = HomeServicesInventory(snapshots: Self.snapshots(piSummary: Self.stressed))
        #expect(inventory.homeAssistants.map(\.serviceID) == [Self.haID, Self.ha2ID])
        #expect(inventory.homeAssistants.map(\.serviceName) == ["Home", "Cabin"])
        #expect(inventory.glances.map(\.serviceID) == [Self.nasID, Self.piID])
        #expect(inventory.glances.first?.summary == Self.healthy)
        #expect(inventory.glances.map(\.id) == inventory.glances.map(\.serviceID))
    }

    @Test func homeAssistantAndEntityLookup() throws {
        let inventory = HomeServicesInventory(snapshots: Self.snapshots())
        let home = try #require(inventory.homeAssistant(Self.haID))
        #expect(home.id == Self.haID)
        #expect(home.entity("scene.movie_night")?.name == "Movie night")
        #expect(home.entity("sensor.living_room_temperature")?.displayState == "21.5 °C")
        #expect(home.entity("light.missing") == nil)
        #expect(inventory.homeAssistant(Self.ha2ID)?.entities.isEmpty == true)
        #expect(inventory.homeAssistant(Self.nasID) == nil)
        #expect(inventory.homeAssistant(UUID()) == nil)
    }

    @Test func glancesOverviewCountsFullFileSystemsAndMemoryPressure() {
        let overview = HomeServicesInventory(snapshots: Self.snapshots(piSummary: Self.stressed)).glancesOverview
        #expect(overview.hosts == 2)
        #expect(overview.fullFileSystems == 2)
        #expect(overview.memoryPressure == 1, "90 % is the inclusive memory threshold")
    }

    @Test func emptyInventory() {
        let inventory = HomeServicesInventory(snapshots: [])
        #expect(inventory.homeAssistants.isEmpty)
        #expect(inventory.glances.isEmpty)
        #expect(inventory.glancesOverview.hosts == 0)
        #expect(inventory.level(kind: .glances, failedServices: 0, totalServices: 0) == .ok)
        #expect(inventory.level(kind: .homeAssistant, failedServices: 0, totalServices: 0) == .ok)
    }

    // MARK: level

    @Test func levelIsCriticalWhenEveryServiceFailed() {
        let inventory = HomeServicesInventory(snapshots: [])
        #expect(inventory.level(kind: .homeAssistant, failedServices: 2, totalServices: 2) == .critical)
        #expect(inventory.level(kind: .glances, failedServices: 1, totalServices: 1) == .critical)
    }

    @Test func levelIsWarningWhenSomeServicesFailed() {
        let inventory = HomeServicesInventory(snapshots: Self.snapshots())
        #expect(inventory.level(kind: .homeAssistant, failedServices: 1, totalServices: 2) == .warning)
        #expect(inventory.level(kind: .glances, failedServices: 1, totalServices: 3) == .warning)
    }

    @Test func levelIsOkWhenHealthy() {
        let inventory = HomeServicesInventory(snapshots: Self.snapshots())
        #expect(inventory.level(kind: .homeAssistant, failedServices: 0, totalServices: 2) == .ok)
        #expect(inventory.level(kind: .glances, failedServices: 0, totalServices: 2) == .ok)
    }

    @Test func glancesThresholdsOnlyWarnTheGlancesCard() {
        let disk = HomeServicesInventory(snapshots: Self.snapshots(nasSummary: GlancesSummary(
            memoryPercent: 10, fileSystems: [.init(mountPoint: "/", percent: 85)]
        )))
        #expect(disk.level(kind: .glances, failedServices: 0, totalServices: 1) == .warning)
        #expect(disk.level(kind: .homeAssistant, failedServices: 0, totalServices: 1) == .ok)

        let memory = HomeServicesInventory(snapshots: Self.snapshots(nasSummary: GlancesSummary(memoryPercent: 90)))
        #expect(memory.level(kind: .glances, failedServices: 0, totalServices: 1) == .warning)
        #expect(memory.level(kind: .homeAssistant, failedServices: 0, totalServices: 1) == .ok)

        let belowThresholds = HomeServicesInventory(snapshots: Self.snapshots(nasSummary: GlancesSummary(
            memoryPercent: 89.9, fileSystems: [.init(mountPoint: "/", percent: 84.9)]
        )))
        #expect(belowThresholds.level(kind: .glances, failedServices: 0, totalServices: 1) == .ok)
    }

    @Test func criticalTakesPrecedenceOverGlancesThresholds() {
        let inventory = HomeServicesInventory(snapshots: Self.snapshots(piSummary: Self.stressed))
        #expect(inventory.level(kind: .glances, failedServices: 2, totalServices: 2) == .critical)
    }
}
