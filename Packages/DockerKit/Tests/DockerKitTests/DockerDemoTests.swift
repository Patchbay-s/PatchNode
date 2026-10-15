import Foundation
import Testing
import PatchNodeCore
@testable import DockerKit

@Suite(.serialized)
struct DockerDemoTests {
    init() {
        DemoServer.register(DockerDemoResponder(portainer: false), host: DemoCatalog.host(for: .dockerSocketProxy))
        DemoServer.register(DockerDemoResponder(portainer: true), host: DemoCatalog.host(for: .dockerPortainer))
    }

    private func client(_ kind: ServiceKind) -> (DockerClient, DemoService) {
        let service = DemoCatalog.services.first { $0.kind == kind }!
        let client = DockerClient(
            flavor: kind == .dockerPortainer ? .portainer : .engine, baseURL: service.url, credential: service.credential,
            httpClient: HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil)
        )
        return (client, service)
    }

    @Test func engineHostLoadsWithDetailsStatsAndLogs() async throws {
        let (client, service) = client(.dockerSocketProxy)
        try await client.checkConnection()
        let snapshot = try await DockerProvider.loadSnapshot(client: client, serviceID: service.id, serviceName: service.name)
        let inventory = DockerInventory(snapshots: [snapshot])
        #expect(inventory.containers.count >= 10)
        #expect(inventory.overview.unhealthy == 1)
        let conditions = inventory.watchedConditions()
        #expect(conditions.count == 1)
        #expect(conditions.first?.kind == .containerUnhealthy)
        let unhealthy = inventory.containers.first { $0.container.name == "service-15" }
        #expect(conditions.first?.scope == unhealthy?.serviceID.uuidString)
        #expect(conditions.first?.key == unhealthy.map { "\($0.host.id)|\($0.container.id)" })
        #expect(inventory.overview.exitedWithError == 1)
        let item = try #require(inventory.containers.first { $0.container.name == "service-08" })
        let details = try await client.details(on: item.host, containerID: item.container.id)
        #expect(details.isRunning)
        let stats = try await client.stats(on: item.host, containerID: item.container.id)
        #expect(stats.cpuPercent != nil)
        let logs = try await client.logs(on: item.host, containerID: item.container.id, tail: 50)
        #expect(logs.count == 50)
    }

    @Test func portainerHasTwoEnvironmentsOneDownAndStacks() async throws {
        let (client, service) = client(.dockerPortainer)
        let snapshot = try await DockerProvider.loadSnapshot(client: client, serviceID: service.id, serviceName: service.name)
        #expect(snapshot.hosts.count == 2)
        #expect(snapshot.stacks.count == 3)
        let inventory = DockerInventory(snapshots: [snapshot])
        #expect(inventory.overview.hostsUnreachable == 1)
        #expect(inventory.containers.count >= 6)
    }

    @Test func simulatedStopAndStartChangeTheState() async throws {
        let (client, service) = client(.dockerSocketProxy)
        let snapshot = try await DockerProvider.loadSnapshot(client: client, serviceID: service.id, serviceName: service.name)
        let host = snapshot.hosts[0].host
        let id = try #require(snapshot.hosts[0].containers.first { $0.name == "service-09" }?.id)
        #expect(try await client.perform(.stop, on: host, containerID: id) == .done)
        #expect(try await !client.details(on: host, containerID: id).isRunning)
        #expect(try await client.perform(.start, on: host, containerID: id) == .done)
        #expect(try await client.details(on: host, containerID: id).isRunning)
    }
}
