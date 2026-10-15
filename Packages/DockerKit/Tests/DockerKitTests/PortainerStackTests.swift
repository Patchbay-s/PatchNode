import Foundation
import Testing
import PatchNodeCore
@testable import DockerKit

@Suite("Portainer stacks API")
struct PortainerStackTests {
    static let baseURL = URL(string: "https://portainer.example.invalid")!
    static let details = #"{"Id":7,"Name":"web","EndpointId":2,"Type":2,"Env":[{"name":"TZ","value":"Europe/Paris"},{"name":"DB_PASSWORD","value":"x"}],"GitConfig":null}"#

    private func client(_ fake: FakeHTTPClient) -> DockerClient {
        DockerClient(flavor: .portainer, baseURL: Self.baseURL, credential: "ptr_fake", httpClient: fake)
    }

    @Test func readsDetailsAndFile() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/stacks/7": .json(Self.details),
            "/api/stacks/7/file": .json(#"{"StackFileContent":"services: {}\n"}"#),
        ])
        let details = try await client(fake).stackDetails(id: 7)
        #expect(details.isCompose && !details.isGitBased)
        #expect(details.environment.count == 2)
        #expect(try await client(fake).stackFile(id: 7) == "services: {}\n")
        let paths = await fake.receivedSpecs.map { $0.url.path() }
        #expect(paths == ["/api/stacks/7", "/api/stacks/7/file"])
        #expect(await fake.receivedSpecs.allSatisfy { $0.headers["X-API-Key"] == "ptr_fake" })
    }

    @Test func updateSendsTheEnvironmentBackUnchangedWithPUT() async throws {
        let fake = FakeHTTPClient(.response(status: 200, body: Data("{}".utf8)))
        let details = try JSONDecoder().decode(PortainerStackDetails.self, from: Data(Self.details.utf8))
        try await client(fake).updateStack(details, content: "services: {}\n", pullImage: true)
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.method == .put)
        #expect(spec.url.path() == "/api/stacks/7")
        #expect(spec.url.query() == "endpointId=2")
        let body = try #require(spec.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stackFileContent"] as? String == "services: {}\n")
        #expect(json["pullImage"] as? Bool == true)
        #expect(json["prune"] as? Bool == false)
        #expect((json["env"] as? [[String: String]])?.map { $0["name"] ?? "" } == ["TZ", "DB_PASSWORD"])
    }

    @Test func gitStacksAreNeverUpdatedThroughTheFile() async throws {
        let fake = FakeHTTPClient(.response(status: 200, body: Data("{}".utf8)))
        let git = try JSONDecoder().decode(PortainerStackDetails.self, from: Data(#"{"Id":8,"Name":"g","EndpointId":2,"Type":2,"GitConfig":{"URL":"https://git.example.com/r"}}"#.utf8))
        #expect(git.isGitBased)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            try await client(fake).updateStack(git, content: "x", pullImage: false)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func startAndStopArePOSTsOnTheStack() async throws {
        let fake = FakeHTTPClient(.response(status: 200, body: Data("{}".utf8)))
        let details = try JSONDecoder().decode(PortainerStackDetails.self, from: Data(Self.details.utf8))
        try await client(fake).setStack(details, running: false)
        try await client(fake).setStack(details, running: true)
        let specs = await fake.receivedSpecs
        #expect(specs.map(\.method) == [.post, .post])
        #expect(specs.map { $0.url.path() } == ["/api/stacks/7/stop", "/api/stacks/7/start"])
    }

    @Test func aDirectEngineHasNoStackAPI() async {
        let fake = FakeHTTPClient(.response(status: 200, body: Data("{}".utf8)))
        let engine = DockerClient(flavor: .engine, baseURL: Self.baseURL, credential: "", httpClient: fake)
        await #expect(throws: ServiceProviderError.invalidResponse) { _ = try await engine.stackFile(id: 1) }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func inventoryFindsTheStackOwningAProject() {
        let serviceID = UUID()
        let host = DockerHost(id: "portainer-2", name: "storage-node", status: .up, portainerEndpointID: 2)
        let inventory = DockerInventory(snapshots: [DockerServiceSnapshot(
            serviceID: serviceID, serviceName: "Portainer",
            hosts: [DockerHostSnapshot(host: host, containers: [])],
            stacks: [PortainerStack(id: 7, name: "web", endpointID: 2, isActive: true), PortainerStack(id: 9, name: "web", endpointID: 3, isActive: true)]
        )])
        let item = inventory.hosts[0]
        #expect(inventory.portainerStack(named: "web", on: item)?.id == 7)
        #expect(inventory.portainerStack(named: "other", on: item) == nil)
    }
}

@Suite("Portainer stack environment safety")
struct PortainerStackEnvTests {
    @Test func anUnreadableEnvFailsInsteadOfBeingWiped() {
        let json = #"{"Id":7,"Name":"web","EndpointId":2,"Type":2,"Env":"not-a-list"}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PortainerStackDetails.self, from: Data(json.utf8)) }
        let null = #"{"Id":7,"Name":"web","EndpointId":2,"Type":2,"Env":null}"#
        #expect((try? JSONDecoder().decode(PortainerStackDetails.self, from: Data(null.utf8)))?.environment == [])
    }
}
