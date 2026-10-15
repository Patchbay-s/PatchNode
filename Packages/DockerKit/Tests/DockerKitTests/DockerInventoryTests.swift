import Foundation
import Testing
import PatchNodeCore
@testable import DockerKit

private let serviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let serviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
private let hostLocal = DockerHost(id: "portainer-1", name: "local", status: .up, portainerEndpointID: 1)
private let hostNAS = DockerHost(id: "portainer-2", name: "storage-node", status: .up, portainerEndpointID: 2)
private let hostDown = DockerHost(id: "portainer-3", name: "offsite", status: .down, portainerEndpointID: 3)
private let engine = DockerHost.engine(name: "docker.example.invalid")

private func c(
    _ name: String, _ state: DockerContainer.State = .running, status: String = "Up 1 hour", project: String? = nil
) -> DockerContainer {
    var labels: [String: String] = [:]
    if let project {
        labels[DockerContainer.composeProjectLabel] = project
        labels[DockerContainer.composeServiceLabel] = name
    }
    return DockerContainer(id: "id-\(name)", name: name, state: state, status: status, labels: labels)
}

private func hostItemID(_ service: UUID, _ host: DockerHost) -> String {
    "\(service.uuidString)|\(host.id)"
}

@Suite struct DockerInventoryGroupingTests {
    @Test func groupsByComposeProjectSortedWithStandaloneLast() throws {
        let snapshot = DockerServiceSnapshot(serviceID: serviceA, serviceName: "Portainer", hosts: [
            DockerHostSnapshot(host: hostLocal, containers: [
                c("service-07"),
                c("service-04", project: "proxy"),
                c("service-09", project: "media"),
                c("service-08", project: "media"),
                c("adminer"),
                c("crowdsec", project: "proxy"),
                c("service-10", project: "Media2"),
            ]),
        ])
        let inventory = DockerInventory(snapshots: [snapshot])
        let groups = try #require(inventory.groupsByHost[hostItemID(serviceA, hostLocal)])
        #expect(groups.map(\.name) == ["media", "Media2", "proxy", nil])
        #expect(groups[0].containers.map(\.container.name) == ["service-08", "service-09"])
        #expect(groups[2].containers.map(\.container.name) == ["crowdsec", "service-04"])
        #expect(groups[3].containers.map(\.container.name) == ["adminer", "service-07"])
        #expect(groups.allSatisfy { $0.hostItemID == hostItemID(serviceA, hostLocal) })
        #expect(groups[3].id == "\(hostItemID(serviceA, hostLocal))|")
    }

    @Test func containersSortedNaturallyByName() throws {
        let snapshot = DockerServiceSnapshot(serviceID: serviceA, serviceName: "Engine", hosts: [
            DockerHostSnapshot(host: engine, containers: [c("web-10"), c("web-2"), c("Web-1")]),
        ])
        let groups = try #require(DockerInventory(snapshots: [snapshot]).groupsByHost[hostItemID(serviceA, engine)])
        #expect(groups.count == 1)
        #expect(groups[0].name == nil)
        #expect(groups[0].containers.map(\.container.name) == ["Web-1", "web-2", "web-10"])
    }

    @Test func stackGroupRunningCount() throws {
        let snapshot = DockerServiceSnapshot(serviceID: serviceA, serviceName: "P", hosts: [
            DockerHostSnapshot(host: hostLocal, containers: [
                c("a", project: "p"), c("b", .exited, status: "Exited (0) 1 hour ago", project: "p"),
            ]),
        ])
        let group = try #require(DockerInventory(snapshots: [snapshot]).groupsByHost.values.first?.first)
        #expect(group.runningCount == 1)
        #expect(group.containers.count == 2)
    }

    @Test func sameProjectOnDifferentHostsAndServicesStaysSeparate() throws {
        let portainer = DockerServiceSnapshot(serviceID: serviceA, serviceName: "Portainer", hosts: [
            DockerHostSnapshot(host: hostLocal, containers: [c("service-04", project: "proxy")]),
            DockerHostSnapshot(host: hostNAS, containers: [c("traefik-nas", project: "proxy")]),
        ])
        let direct = DockerServiceSnapshot(serviceID: serviceB, serviceName: "Engine", hosts: [
            DockerHostSnapshot(host: hostLocal, containers: [c("traefik-b", project: "proxy")]),
        ])
        let inventory = DockerInventory(snapshots: [portainer, direct])
        #expect(inventory.hosts.count == 3)
        #expect(inventory.groupsByHost.count == 3)
        #expect(inventory.groupsByHost[hostItemID(serviceA, hostLocal)]?.flatMap(\.containers).map(\.container.name) == ["service-04"])
        #expect(inventory.groupsByHost[hostItemID(serviceA, hostNAS)]?.flatMap(\.containers).map(\.container.name) == ["traefik-nas"])
        #expect(inventory.groupsByHost[hostItemID(serviceB, hostLocal)]?.flatMap(\.containers).map(\.container.name) == ["traefik-b"])
        // Container item ids stay unique across services even with the same host id.
        #expect(Set(inventory.containers.map(\.id)).count == 3)
        #expect(Set(inventory.hosts.map(\.id)).count == 3)
    }

    @Test func hostItemCounts() throws {
        let snapshot = DockerServiceSnapshot(serviceID: serviceA, serviceName: "Portainer", hosts: [
            DockerHostSnapshot(host: hostLocal, containers: [
                c("a"), c("b"), c("c", .exited, status: "Exited (0) 2 days ago"), c("d", .paused),
            ]),
            DockerHostSnapshot(host: hostNAS, containers: [], error: .unexpectedStatus(500)),
        ])
        let inventory = DockerInventory(snapshots: [snapshot])
        let local = try #require(inventory.hosts.first)
        #expect(local.runningCount == 2)
        #expect(local.totalCount == 4)
        #expect(local.isReachable)
        #expect(local.serviceName == "Portainer")
        let nas = try #require(inventory.hosts.last)
        #expect(nas.totalCount == 0)
        #expect(nas.error == .unexpectedStatus(500))
        #expect(!nas.isReachable)
        #expect(inventory.groupsByHost[nas.id] == [])
    }
}

@Suite struct DockerOverviewTests {
    private func overview(_ hosts: [DockerHostSnapshot]) -> DockerOverview {
        DockerInventory(snapshots: [DockerServiceSnapshot(serviceID: serviceA, serviceName: "P", hosts: hosts)]).overview
    }

    @Test func countsAcrossHosts() {
        let o = overview([
            DockerHostSnapshot(host: hostLocal, containers: [
                c("ok", status: "Up 2 hours (healthy)"),
                c("sick", status: "Up 2 hours (unhealthy)"),
                c("loop", .restarting, status: "Restarting (1) 3 seconds ago"),
                c("crashed", .exited, status: "Exited (1) 5 minutes ago"),
                c("done", .exited, status: "Exited (0) 1 day ago"),
            ]),
            DockerHostSnapshot(host: hostNAS, containers: [c("nas-app"), c("nas-new", .created, status: "Created")]),
            DockerHostSnapshot(host: hostDown, containers: [], error: .unreachable),
            DockerHostSnapshot(host: engine, containers: [], error: .unexpectedStatus(502)),
        ])
        #expect(o.running == 3)
        #expect(o.total == 7)
        #expect(o.stopped == 4)
        #expect(o.unhealthy == 1)
        #expect(o.restarting == 1)
        #expect(o.exitedWithError == 1)
        #expect(o.hostsTotal == 4)
        #expect(o.hostsUnreachable == 2)
    }

    @Test func downHostWithoutErrorCountsAsUnreachable() {
        let o = overview([
            DockerHostSnapshot(host: hostLocal, containers: [c("a")]),
            DockerHostSnapshot(host: hostDown, containers: []),
        ])
        #expect(o.hostsUnreachable == 1)
        #expect(o.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func emptyInventoryIsOK() {
        let o = DockerInventory(snapshots: []).overview
        #expect(o.total == 0)
        #expect(o.hostsTotal == 0)
        #expect(o.level(failedServices: 0, totalServices: 0) == .ok)
    }

    @Test func allServicesFailedIsCritical() {
        let o = DockerInventory(snapshots: []).overview
        #expect(o.level(failedServices: 2, totalServices: 2) == .critical)
        #expect(o.level(failedServices: 1, totalServices: 1) == .critical)
    }

    @Test func allHostsUnreachableIsCritical() {
        let o = overview([
            DockerHostSnapshot(host: hostLocal, containers: [], error: .unreachable),
            DockerHostSnapshot(host: hostDown, containers: []),
        ])
        #expect(o.level(failedServices: 0, totalServices: 1) == .critical)
    }

    @Test func healthyInventoryIsOK() {
        let o = overview([DockerHostSnapshot(host: hostLocal, containers: [
            c("a", status: "Up 1 hour (healthy)"), c("b", .exited, status: "Exited (0) 1 day ago"), c("c", .paused),
        ])])
        #expect(o.level(failedServices: 0, totalServices: 1) == .ok)
    }

    @Test(arguments: [
        ("unhealthy", DockerContainer.State.running, "Up 1 hour (unhealthy)"),
        ("restarting", .restarting, "Restarting (1) 2 seconds ago"),
        ("exitedWithError", .exited, "Exited (137) 3 hours ago"),
    ])
    func problematicContainerIsWarning(label: String, state: DockerContainer.State, status: String) {
        let o = overview([DockerHostSnapshot(host: hostLocal, containers: [c("fine"), c(label, state, status: status)])])
        #expect(o.level(failedServices: 0, totalServices: 1) == .warning, "\(label)")
    }

    @Test func oneHostDownAmongSeveralIsWarning() {
        let o = overview([
            DockerHostSnapshot(host: hostLocal, containers: [c("a")]),
            DockerHostSnapshot(host: hostNAS, containers: [], error: .unexpectedStatus(500)),
        ])
        #expect(o.level(failedServices: 0, totalServices: 1) == .warning)
    }

    @Test func oneFailedServiceAmongSeveralIsWarning() {
        let o = overview([DockerHostSnapshot(host: hostLocal, containers: [c("a")])])
        #expect(o.level(failedServices: 1, totalServices: 2) == .warning)
    }
}
