import Foundation
import Testing
@testable import PatchNodeCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func family(_ id: String, _ level: SharedSnapshot.Family.Level) -> SharedSnapshot.Family {
    SharedSnapshot.Family(id: id, title: id, level: level, headline: "\(id) headline")
}

private func tempStore() -> SharedSnapshotStore {
    let dir = FileManager.default.temporaryDirectory.appending(path: "PatchNode-tests-\(UUID().uuidString)")
    return SharedSnapshotStore(fileURL: dir.appending(path: SharedSnapshotStore.fileName))
}

@Suite("SharedSnapshot")
struct SharedSnapshotTests {
    @Test func globalLevelIsTheWorstKnownLevel() {
        #expect(SharedSnapshot(generatedAt: t0).globalLevel == .unknown)
        #expect(SharedSnapshot(generatedAt: t0, families: [family("a", .unknown)]).globalLevel == .unknown)
        #expect(SharedSnapshot(generatedAt: t0, families: [family("a", .ok), family("b", .unknown)]).globalLevel == .ok)
        #expect(SharedSnapshot(generatedAt: t0, families: [family("a", .ok), family("b", .warning)]).globalLevel == .warning)
        #expect(SharedSnapshot(generatedAt: t0, families: [family("a", .critical), family("b", .warning)]).globalLevel == .critical)
    }

    @Test func countsOkAndAlerts() {
        let snapshot = SharedSnapshot(generatedAt: t0, families: [
            family("a", .ok), family("b", .ok), family("c", .warning), family("d", .critical), family("e", .unknown),
        ])
        #expect(snapshot.okCount == 2)
        #expect(snapshot.alertCount == 2)
        #expect(snapshot.knownFamilies.count == 4)
    }

    @Test func staleAfterOneHour() {
        let snapshot = SharedSnapshot(generatedAt: t0)
        #expect(!snapshot.isStale(at: t0.addingTimeInterval(3600)))
        #expect(snapshot.isStale(at: t0.addingTimeInterval(3601)))
    }

    @Test func sameContentIgnoresTheDate() {
        let a = SharedSnapshot(generatedAt: t0, families: [family("a", .ok)])
        var b = a
        b.generatedAt = t0.addingTimeInterval(60)
        #expect(a.hasSameContent(as: b))
        b.families = [family("a", .warning)]
        #expect(!a.hasSameContent(as: b))
    }

    @Test func boundedCapsLists() {
        let issues = (0..<50).map { SharedSnapshot.ContainerIssue(id: "\($0)", name: "c\($0)", host: "h", kind: .stopped) }
        let nodes = (0..<30).map { SharedSnapshot.NodeLoad(id: "\($0)", title: "n\($0)", isOnline: true, cpu: 0.1, memory: 0.2) }
        let bounded = SharedSnapshot(generatedAt: t0, nodes: nodes, containerIssues: issues).bounded(nodes: 5, issues: 3)
        #expect(bounded.nodes.map(\.id) == ["0", "1", "2", "3", "4"])
        #expect(bounded.containerIssues.count == 3)
    }
}

@Suite("SharedSnapshotStore")
struct SharedSnapshotStoreTests {
    @Test func writeThenReadRoundTrips() throws {
        let store = tempStore()
        defer { store.delete() }
        let serviceID = UUID()
        let snapshot = SharedSnapshot(
            generatedAt: t0,
            families: [family("proxmox", .warning)],
            nodes: [.init(id: "n", title: "Test Site · node-1", isOnline: true, cpu: 0.25, memory: 0.5)],
            containerIssues: [.init(id: "c", name: "test-container", host: "docker", kind: .unhealthy)],
            guests: [.init(id: "g", serviceID: serviceID, serviceName: "Test Site", node: "node-1", type: "qemu", vmid: 100, name: "test-app")],
            containers: [.init(id: "k", serviceID: serviceID, serviceName: "Test proxy", endpointID: 2, containerID: "abc", name: "test-container", host: "docker")]
        )
        try store.write(snapshot)
        #expect(store.read() == snapshot)
    }

    @Test func missingOrCorruptFileReadsAsNil() throws {
        let store = tempStore()
        defer { store.delete() }
        #expect(store.read() == nil)
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.read() == nil)
    }

    @Test func otherFormatVersionIsIgnored() throws {
        let store = tempStore()
        defer { store.delete() }
        var snapshot = SharedSnapshot(generatedAt: t0)
        snapshot.version = 99
        try store.write(snapshot)
        #expect(store.read() == nil)
    }

    /// The file is read by widgets, possibly on the lock screen: nothing secret.
    @Test func fileHoldsNoURLOrCredentialField() throws {
        let store = tempStore()
        defer { store.delete() }
        try store.write(SharedSnapshot(generatedAt: t0, guests: [
            .init(id: "g", serviceID: UUID(), serviceName: "Test Site", node: "node-1", type: "qemu", vmid: 100, name: "test-app"),
        ]))
        let text = try String(contentsOf: store.fileURL, encoding: .utf8).lowercased()
        // JSONEncoder escapes "/" as "\/": check both spellings of a URL.
        for forbidden in ["https://", "https:\\/\\/", "token", "password", "secret", "authorization"] {
            #expect(!text.contains(forbidden), "shared snapshot contains \(forbidden)")
        }
    }
}

struct WidgetCacheStatusTests {
    @Test func emptyThenWrittenWithCounts() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "PatchNode-status-\(UUID().uuidString)/snapshot.json")
        let store = SharedSnapshotStore(fileURL: url)
        #expect(store.status() == .empty)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try store.write(SharedSnapshot(
            generatedAt: date,
            families: [.init(id: "proxmox", title: "Proxmox", level: .ok, headline: "2/2"),
                       .init(id: "docker", title: "Docker", level: .warning, headline: "9/10")],
            nodes: [.init(id: "n1", title: "node-a", isOnline: true, cpu: 0.2, memory: 0.5)]
        ))
        #expect(store.status() == .written(at: date, families: 2, nodes: 1, guests: 0, containers: 0))
        store.delete()
        #expect(store.status() == .empty)
    }
}
