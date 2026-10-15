import Foundation
import Testing
import PatchNodeCore
@testable import DockerKit

/// Phase 7: mapping of the Docker inventory to the snapshot shared with the
/// widgets and App Intents. Containers are decoded from realistic
/// `GET /containers/json?all=true` payloads.
private enum SharedFixtures {
    static let portainerID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let engineID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    static let local = DockerHost(id: "portainer-1", name: "local", status: .up, portainerEndpointID: 1)
    static let nas = DockerHost(id: "portainer-2", name: "storage-node", status: .down, portainerEndpointID: 2)
    static let engine = DockerHost.engine(name: "docker-engine")

    static func container(_ name: String, state: String, status: String) -> String {
        let id = String(repeating: String(name.utf8.count % 10), count: 64)
        return #"""
        {"Id":"\#(name)-\#(id)","Names":["/\#(name)"],"Image":"example/\#(name):latest",
         "Created":1714557600,"Ports":[],"Labels":{},"State":"\#(state)","Status":"\#(status)"}
        """#
    }

    static let localContainers = "[" + [
        container("service-04", state: "running", status: "Up 3 hours (healthy)"),
        container("service-09", state: "running", status: "Up 2 hours (unhealthy)"),
        container("backup-job", state: "exited", status: "Exited (137) 3 hours ago"),
        container("postgres", state: "restarting", status: "Restarting (1) 5 seconds ago"),
        container("adminer", state: "exited", status: "Exited (0) 2 days ago"),
        container("service-07", state: "running", status: "Up 5 days"),
    ].joined(separator: ",") + "]"

    static let nasContainers = "[" + [
        container("service-08", state: "running", status: "Up 10 seconds (health: starting)"),
        container("service-10", state: "running", status: "Up 1 hour (unhealthy)"),
        container("homepage", state: "paused", status: "Up 3 hours (Paused)"),
        container("grafana", state: "created", status: "Created"),
    ].joined(separator: ",") + "]"

    static let engineContainers = "[" + [
        container("web-10", state: "exited", status: "Exited (1) 1 hour ago"),
        container("web-2", state: "exited", status: "Exited (2) 1 hour ago"),
        container("Web-1", state: "dead", status: "Dead"),
        container("service-01", state: "running", status: "Up 7 hours"),
    ].joined(separator: ",") + "]"
}

private typealias SF = SharedFixtures

private func decode(_ json: String) throws -> [DockerContainer] {
    try JSONDecoder().decode([DockerContainer].self, from: Data(json.utf8))
}

private func inventory() throws -> DockerInventory {
    DockerInventory(snapshots: [
        DockerServiceSnapshot(serviceID: SF.portainerID, serviceName: "Portainer demo", hosts: [
            DockerHostSnapshot(host: SF.local, containers: try decode(SF.localContainers)),
            DockerHostSnapshot(host: SF.nas, containers: try decode(SF.nasContainers)),
        ]),
        DockerServiceSnapshot(serviceID: SF.engineID, serviceName: "Docker NUC", hosts: [
            DockerHostSnapshot(host: SF.engine, containers: try decode(SF.engineContainers)),
        ]),
    ])
}

private func tempStore() -> SharedSnapshotStore {
    let dir = FileManager.default.temporaryDirectory.appending(path: "PatchNode-docker-tests-\(UUID().uuidString)")
    return SharedSnapshotStore(fileURL: dir.appending(path: SharedSnapshotStore.fileName))
}

@Suite("Docker → shared snapshot: container issues")
struct DockerSharedIssueTests {
    @Test func issuesAreOrderedByKindThenNaturalName() throws {
        let issues = try inventory().sharedContainerIssues()
        #expect(issues.map(\.name) == [
            "service-09", "service-10",
            "backup-job", "web-2", "web-10",
            "postgres",
            "adminer", "grafana", "homepage", "Web-1",
        ])
        #expect(issues.map(\.kind) == [
            .unhealthy, .unhealthy,
            .exitedWithError, .exitedWithError, .exitedWithError,
            .restarting,
            .stopped, .stopped, .stopped, .stopped,
        ])
    }

    @Test func runningContainersWithoutProblemAreExcluded() throws {
        let names = Set(try inventory().sharedContainerIssues().map(\.name))
        for healthy in ["service-04", "service-07", "service-08", "service-01"] {
            #expect(!names.contains(healthy), "\(healthy) should not be an issue")
        }
    }

    @Test func kindsMatchTheContainerState() throws {
        let issues = try inventory().sharedContainerIssues()
        let byName = Dictionary(uniqueKeysWithValues: issues.map { ($0.name, $0.kind) })
        #expect(byName["service-09"] == .unhealthy)
        #expect(byName["backup-job"] == .exitedWithError)
        #expect(byName["postgres"] == .restarting)
        #expect(byName["adminer"] == .stopped)
        #expect(byName["homepage"] == .stopped)
        #expect(byName["grafana"] == .stopped)
        #expect(byName["Web-1"] == .stopped)
    }

    @Test func unhealthyWinsOverRestarting() throws {
        let flapping = try decode("[" + SF.container("mqtt", state: "restarting", status: "Restarting (1) 2 seconds ago (unhealthy)") + "]")
        let inv = DockerInventory(snapshots: [
            DockerServiceSnapshot(serviceID: SF.engineID, serviceName: "Docker NUC", hosts: [
                DockerHostSnapshot(host: SF.engine, containers: flapping),
            ]),
        ])
        #expect(inv.sharedContainerIssues().map(\.kind) == [.unhealthy])
    }

    @Test func issuesCarryTheHostNameAndTheItemID() throws {
        let inv = try inventory()
        let issues = inv.sharedContainerIssues()
        let byName = Dictionary(uniqueKeysWithValues: issues.map { ($0.name, $0) })
        #expect(byName["service-09"]?.host == "local")
        #expect(byName["service-10"]?.host == "storage-node")
        #expect(byName["web-2"]?.host == "docker-engine")
        let ids = Set(inv.containers.map(\.id))
        #expect(issues.allSatisfy { ids.contains($0.id) })
        #expect(Set(issues.map(\.id)).count == issues.count)
    }

    @Test func emptyInventoryHasNoIssuesOrTargets() {
        let empty = DockerInventory(snapshots: [])
        #expect(empty.sharedContainerIssues().isEmpty)
        #expect(empty.sharedContainerTargets().isEmpty)
    }
}

@Suite("Docker → shared snapshot: container targets")
struct DockerSharedTargetTests {
    @Test func everyContainerIsATargetWithItsIdentity() throws {
        let inv = try inventory()
        let targets = inv.sharedContainerTargets()
        #expect(targets.count == inv.containers.count)
        #expect(targets.map(\.id) == inv.containers.map(\.id))
        #expect(targets.map(\.containerID) == inv.containers.map(\.container.id))
        #expect(targets.map(\.name) == inv.containers.map(\.container.name))
    }

    @Test func targetsCarryServiceNameAndHostName() throws {
        let targets = try inventory().sharedContainerTargets()
        let testContainer = try #require(targets.first { $0.name == "service-09" })
        #expect(testContainer.serviceID == SF.portainerID)
        #expect(testContainer.serviceName == "Portainer demo")
        #expect(testContainer.host == "local")
        let testService = try #require(targets.first { $0.name == "service-10" })
        #expect(testService.serviceName == "Portainer demo")
        #expect(testService.host == "storage-node")
        let nginx = try #require(targets.first { $0.name == "service-01" })
        #expect(nginx.serviceID == SF.engineID)
        #expect(nginx.serviceName == "Docker NUC")
        #expect(nginx.host == "docker-engine")
    }

    @Test func portainerTargetsHaveTheirEndpointIDAndEngineTargetsNone() throws {
        let targets = try inventory().sharedContainerTargets()
        #expect(targets.first { $0.name == "service-09" }?.endpointID == 1)
        #expect(targets.first { $0.name == "service-10" }?.endpointID == 2)
        let engineTargets = targets.filter { $0.serviceID == SF.engineID }
        #expect(engineTargets.count == 4)
        #expect(engineTargets.allSatisfy { $0.endpointID == nil })
    }

    @Test func hostRebuiltFromTargetMatchesTheOriginalHost() throws {
        let inv = try inventory()
        let targets = inv.sharedContainerTargets()
        for (target, item) in zip(targets, inv.containers) {
            let host = DockerHost(shared: target)
            #expect(host.id == item.host.id)
            #expect(host.portainerEndpointID == item.host.portainerEndpointID)
            #expect(host.name == item.host.name)
        }
    }

    @Test func hostRebuiltFromPortainerTargetIsPortainerEndpoint() {
        let target = SharedSnapshot.ContainerTarget(
            id: "x", serviceID: SF.portainerID, serviceName: "Portainer demo", endpointID: 7,
            containerID: "abc", name: "service-09", host: "server-b"
        )
        let host = DockerHost(shared: target)
        #expect(host.id == "portainer-7")
        #expect(host.portainerEndpointID == 7)
        #expect(host.name == "server-b")
    }

    @Test func hostRebuiltFromEngineTargetIsEngine() {
        let target = SharedSnapshot.ContainerTarget(
            id: "x", serviceID: SF.engineID, serviceName: "Docker NUC", endpointID: nil,
            containerID: "abc", name: "service-01", host: "docker-engine"
        )
        let host = DockerHost(shared: target)
        #expect(host == DockerHost.engine(name: "docker-engine"))
        #expect(host.id == "engine")
        #expect(host.portainerEndpointID == nil)
    }
}

@Suite("Docker → shared snapshot: store round trip")
struct DockerSharedStoreTests {
    @Test func mappedSnapshotRoundTripsThroughTheStoreWithoutSecrets() throws {
        let inv = try inventory()
        let snapshot = SharedSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            containerIssues: inv.sharedContainerIssues(),
            containers: inv.sharedContainerTargets()
        )
        let store = tempStore()
        defer { store.delete() }
        try store.write(snapshot)
        let read = try #require(store.read())
        #expect(read == snapshot)
        #expect(read.containers.map { DockerHost(shared: $0).id } == inv.containers.map(\.host.id))

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.contains("https://"))
        #expect(!text.contains(#"https:\/\/"#))
        #expect(!text.contains(DockerFixtures.portainerKey))
        #expect(!text.contains(DockerFixtures.engineBasic))
        #expect(!text.contains("example.invalid"))
    }
}
