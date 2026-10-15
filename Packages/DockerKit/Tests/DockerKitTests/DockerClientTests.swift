import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import DockerKit

private typealias F = DockerFixtures

private let portainerHost = DockerHost(id: "portainer-1", name: "local", status: .up, portainerEndpointID: 1)
private let engineHost = DockerHost.engine(name: "docker.example.invalid")

private func portainerClient(_ fake: FakeHTTPClient) -> DockerClient {
    DockerClient(flavor: .portainer, baseURL: F.portainerURL, credential: F.portainerKey, httpClient: fake)
}

private func engineClient(_ fake: FakeHTTPClient, credential: String = F.engineCredential) -> DockerClient {
    DockerClient(flavor: .engine, baseURL: F.engineURL, credential: credential, httpClient: fake)
}

/// Every client call that talks to the server, for the error-mapping matrix.
enum ClientCall: String, CaseIterable, Sendable {
    case hosts, containers, details, stats, stacks, checkConnection

    func run(_ client: DockerClient, host: DockerHost) async throws {
        switch self {
        case .hosts: _ = try await client.hosts()
        case .containers: _ = try await client.containers(on: host)
        case .details: _ = try await client.details(on: host, containerID: F.containerID)
        case .stats: _ = try await client.stats(on: host, containerID: F.containerID)
        case .stacks: _ = try await client.stacks()
        case .checkConnection: try await client.checkConnection()
        }
    }

    /// Calls that go over the network for this flavor.
    static func networked(_ flavor: DockerAPIFlavor) -> [ClientCall] {
        switch flavor {
        case .portainer: return allCases
        case .engine: return [.containers, .details, .stats, .checkConnection]
        }
    }

    /// Calls that decode a JSON body (checkConnection on the engine only needs a 200).
    static func decoding(_ flavor: DockerAPIFlavor) -> [ClientCall] {
        switch flavor {
        case .portainer: return allCases
        case .engine: return [.containers, .details, .stats]
        }
    }
}

private func client(_ flavor: DockerAPIFlavor, _ fake: FakeHTTPClient) -> (DockerClient, DockerHost) {
    flavor == .portainer ? (portainerClient(fake), portainerHost) : (engineClient(fake), engineHost)
}

private let flavors: [DockerAPIFlavor] = [.portainer, .engine]

@Suite struct DockerClientURLTests {
    // MARK: Portainer URLs

    @Test func portainerHostsRequestsEndpointsList() async throws {
        let fake = FakeHTTPClient.json(F.endpoints)
        _ = try await portainerClient(fake).hosts()
        #expect(await fake.receivedURLs == ["https://portainer.example.invalid/api/endpoints"])
        #expect(await fake.receivedSpecs.first?.method == .get)
    }

    @Test func portainerCheckConnectionUsesEndpointsList() async throws {
        let fake = FakeHTTPClient.json(F.endpoints)
        try await portainerClient(fake).checkConnection()
        #expect(await fake.receivedURLs == ["https://portainer.example.invalid/api/endpoints"])
    }

    @Test func portainerContainersURLIsRelayedUnderEndpoint() async throws {
        let fake = FakeHTTPClient.json(F.containers)
        _ = try await portainerClient(fake).containers(on: portainerHost)
        #expect(await fake.receivedURLs == ["https://portainer.example.invalid/api/endpoints/1/docker/containers/json?all=true"])
    }

    @Test func portainerDetailsStatsLogsAndStacksURLs() async throws {
        let detailsFake = FakeHTTPClient.json(F.details)
        _ = try await portainerClient(detailsFake).details(on: portainerHost, containerID: F.containerID)
        #expect(await detailsFake.receivedURLs == ["https://portainer.example.invalid/api/endpoints/1/docker/containers/\(F.containerID)/json"])

        let statsFake = FakeHTTPClient.json(F.stats)
        _ = try await portainerClient(statsFake).stats(on: portainerHost, containerID: F.containerID)
        #expect(await statsFake.receivedURLs == ["https://portainer.example.invalid/api/endpoints/1/docker/containers/\(F.containerID)/stats?stream=false"])

        let logsFake = FakeHTTPClient.json("")
        _ = try await portainerClient(logsFake).logs(on: portainerHost, containerID: F.containerID)
        #expect(await logsFake.receivedURLs == ["https://portainer.example.invalid/api/endpoints/1/docker/containers/\(F.containerID)/logs?stdout=true&stderr=true&tail=200&timestamps=true"])

        let stacksFake = FakeHTTPClient.json(F.stacks)
        _ = try await portainerClient(stacksFake).stacks()
        #expect(await stacksFake.receivedURLs == ["https://portainer.example.invalid/api/stacks"])
    }

    @Test func portainerContainersOnHostWithoutEndpointIDIsRejectedBeforeSending() async {
        let fake = FakeHTTPClient.json(F.containers)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await portainerClient(fake).containers(on: .engine(name: "x"))
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    // MARK: Engine URLs

    @Test func engineContainersDetailsStatsLogsURLs() async throws {
        let listFake = FakeHTTPClient.json(F.containers)
        _ = try await engineClient(listFake).containers(on: engineHost)
        #expect(await listFake.receivedURLs == ["https://docker.example.invalid/containers/json?all=true"])

        let detailsFake = FakeHTTPClient.json(F.details)
        _ = try await engineClient(detailsFake).details(on: engineHost, containerID: F.containerID)
        #expect(await detailsFake.receivedURLs == ["https://docker.example.invalid/containers/\(F.containerID)/json"])

        let statsFake = FakeHTTPClient.json(F.stats)
        _ = try await engineClient(statsFake).stats(on: engineHost, containerID: F.containerID)
        #expect(await statsFake.receivedURLs == ["https://docker.example.invalid/containers/\(F.containerID)/stats?stream=false"])

        let logsFake = FakeHTTPClient.json("")
        _ = try await engineClient(logsFake).logs(on: engineHost, containerID: F.containerID, tail: 50)
        #expect(await logsFake.receivedURLs == ["https://docker.example.invalid/containers/\(F.containerID)/logs?stdout=true&stderr=true&tail=50&timestamps=true"])
    }

    @Test func engineCheckConnectionRequestsVersion() async throws {
        let fake = FakeHTTPClient.json(#"{"Version":"26.1.4","ApiVersion":"1.45","Os":"linux","Arch":"amd64"}"#)
        try await engineClient(fake).checkConnection()
        #expect(await fake.receivedURLs == ["https://docker.example.invalid/version"])
    }

    @Test func engineHostsReturnsSingleHostNamedAfterServiceWithoutRequest() async throws {
        let fake = FakeHTTPClient.json(F.endpoints)
        let client = DockerClient(flavor: .engine, baseURL: F.engineURL, credential: F.engineCredential, httpClient: fake, engineName: "Docker NUC")
        let hosts = try await client.hosts()
        #expect(hosts == [DockerHost(id: "engine", name: "Docker NUC", status: .up)])
        #expect(hosts.first?.portainerEndpointID == nil)
        #expect(await fake.receivedSpecs.isEmpty)
    }

    /// The engine's name reaches the widgets and Siri: it must never be the host.
    @Test func engineHostNameIsNeverTheURLHost() async throws {
        let hosts = try await engineClient(FakeHTTPClient.json(F.endpoints)).hosts()
        #expect(hosts.map(\.name) == ["Docker"])
        #expect(!hosts.contains { $0.name.contains("example.invalid") })
    }

    @Test func engineStacksReturnsEmptyWithoutRequest() async throws {
        let fake = FakeHTTPClient.json(F.stacks)
        let stacks = try await engineClient(fake).stacks()
        #expect(stacks.isEmpty)
        #expect(await fake.receivedSpecs.isEmpty)
    }

    // MARK: Log tail clamping

    @Test(arguments: [(-5, "1"), (0, "1"), (1, "1"), (200, "200"), (5000, "5000"), (5001, "5000"), (Int.max, "5000")])
    func logTailIsClampedBetween1And5000(tail: Int, expected: String) async throws {
        let fake = FakeHTTPClient.json("")
        _ = try await engineClient(fake).logs(on: engineHost, containerID: "web", tail: tail)
        let url = try #require(await fake.receivedSpecs.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "tail" }?.value == expected)
    }

    @Test func logsUsesDefaultTailOf200() async throws {
        #expect(DockerClient.defaultLogTail == 200)
        #expect(DockerClient.maxLogTail == 5000)
    }

    // MARK: Path injection

    @Test(arguments: ["", ".", "..", "../../version", "a/b", "/traefik", "web?all=1", "web#x", "web%2F", "web name", "wéb"])
    func unsafeContainerIDIsRejectedBeforeSending(id: String) async {
        for flavor in flavors {
            let fake = FakeHTTPClient.json(F.details)
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.invalidResponse) {
                _ = try await client.details(on: host, containerID: id)
            }
            await #expect(throws: ServiceProviderError.invalidResponse) {
                _ = try await client.stats(on: host, containerID: id)
            }
            await #expect(throws: ServiceProviderError.invalidResponse) {
                _ = try await client.logs(on: host, containerID: id)
            }
            #expect(await fake.receivedSpecs.isEmpty)
        }
    }

    @Test(arguments: ["service-04", "my_app-1.web", F.containerID])
    func safeContainerIDsAreAccepted(id: String) async throws {
        let fake = FakeHTTPClient.json(F.details)
        _ = try await engineClient(fake).details(on: engineHost, containerID: id)
        #expect(await fake.receivedPaths == ["/containers/\(id)/json"])
    }
}

@Suite struct DockerClientHeaderTests {
    @Test func portainerSendsOnlyAPIKeyHeader() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(F.endpoints),
            "/api/endpoints/1/docker/containers/json": .json(F.containers),
            "/api/stacks": .json(F.stacks),
        ])
        let client = portainerClient(fake)
        _ = try await client.hosts()
        _ = try await client.containers(on: portainerHost)
        _ = try await client.stacks()
        let specs = await fake.receivedSpecs
        #expect(specs.count == 3)
        for spec in specs {
            #expect(spec.headers == ["X-API-Key": F.portainerKey])
            #expect(spec.body == nil)
        }
    }

    @Test func engineSendsBasicAuthorization() async throws {
        let fake = FakeHTTPClient.json(F.containers)
        _ = try await engineClient(fake).containers(on: engineHost)
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.headers == ["Authorization": F.engineBasic])
    }

    @Test func engineWithEmptyCredentialSendsNoAuthorizationHeader() async throws {
        let fake = FakeHTTPClient.json(F.containers)
        _ = try await engineClient(fake, credential: "").containers(on: engineHost)
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.headers.isEmpty)
    }

    @Test func credentialsNeverAppearInRedactedDescription() async throws {
        let portainerFake = FakeHTTPClient.json(F.containers)
        _ = try await portainerClient(portainerFake).containers(on: portainerHost)
        let engineFake = FakeHTTPClient.json(F.containers)
        _ = try await engineClient(engineFake).containers(on: engineHost)

        let portainerLog = try #require(await portainerFake.receivedSpecs.first).redactedDescription
        let engineLog = try #require(await engineFake.receivedSpecs.first).redactedDescription
        #expect(!portainerLog.contains(F.portainerKey))
        #expect(portainerLog.contains("X-API-Key: <redacted>"))
        #expect(!engineLog.contains("bW9uaXRvcjpmYWtlLXBhc3N3b3Jk"))
        #expect(!engineLog.contains("fake-password"))
        #expect(engineLog.contains("Authorization: <redacted>"))
    }

    @Test func nonHTTPSBaseURLIsRejectedBeforeAnyNetworkAccess() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = DockerClient(
            flavor: .engine, baseURL: URL(string: "http://docker.example.invalid")!,
            credential: F.engineCredential, httpClient: HTTPClient(session: session, maxAttempts: 1)
        )
        // The core client throws nonHTTPSURL, mapped by fetchOK to .unreachable.
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await client.containers(on: engineHost)
        }
        #expect(RecordingURLProtocol.startedCount.value == 0)
    }
}

@Suite struct DockerClientErrorTests {
    @Test func portainerDecodesNominalResponses() async throws {
        let fake = FakeHTTPClient(routes: [
            "/api/endpoints": .json(F.endpoints),
            "/api/endpoints/1/docker/containers/json": .json(F.containers),
            "/api/endpoints/1/docker/containers/\(F.containerID)/json": .json(F.details),
            "/api/endpoints/1/docker/containers/\(F.containerID)/stats": .json(F.stats),
            "/api/stacks": .json(F.stacks),
        ])
        let client = portainerClient(fake)
        let hosts = try await client.hosts()
        #expect(hosts.map(\.name) == ["local", "storage-node", "server-b"])
        #expect(try await client.containers(on: portainerHost).count == 3)
        #expect(try await client.details(on: portainerHost, containerID: F.containerID).restartPolicy == "unless-stopped")
        #expect(try await client.stats(on: portainerHost, containerID: F.containerID).onlineCPUs == 4)
        let stacks = try await client.stacks()
        #expect(stacks == [
            PortainerStack(id: 1, name: "proxy", endpointID: 1, isActive: true),
            PortainerStack(id: 2, name: "media", endpointID: 1, isActive: false),
        ])
    }

    @Test func engineDecodesNominalLogs() async throws {
        var body = F.frame(1, "2024-05-01T10:00:00.000000000Z server started\n")
        body += F.frame(2, "2024-05-01T10:00:01.000000000Z warning: low disk\n")
        let fake = FakeHTTPClient(.response(status: 200, body: Data(body)))
        let lines = try await engineClient(fake).logs(on: engineHost, containerID: "web")
        #expect(lines.map(\.text) == ["server started", "warning: low disk"])
        #expect(lines.map(\.stream) == [.stdout, .stderr])
        #expect(lines.allSatisfy { $0.timestamp != nil })
    }

    @Test func portainerEndpointsOfKubernetesAndAzureTypesAreFilteredOut() async throws {
        let hosts = try await portainerClient(FakeHTTPClient.json(F.endpoints)).hosts()
        #expect(hosts.compactMap(\.portainerEndpointID) == [1, 2, 4])
        #expect(hosts.map(\.id) == ["portainer-1", "portainer-2", "portainer-4"])
    }

    @Test func portainerEndpointStatusMapsToHostStatus() async throws {
        let json = """
        [{"Id": 1, "Name": "up", "Type": 1, "Status": 1},
         {"Id": 2, "Name": "down", "Type": 2, "Status": 2},
         {"Id": 3, "Name": "unknown", "Type": 1},
         {"Id": 4, "Type": 1, "Status": 1},
         {"Name": "no-id", "Type": 1, "Status": 1}]
        """
        let hosts = try await portainerClient(FakeHTTPClient.json(json)).hosts()
        #expect(hosts.map(\.status) == [.up, .down, .unknown, .up])
        #expect(hosts.last?.name == "#4")
    }

    @Test(arguments: flavors)
    func unauthorized401MapsToUnauthorizedWithoutRetry(flavor: DockerAPIFlavor) async {
        for call in ClientCall.networked(flavor) {
            let fake = FakeHTTPClient(.unauthorized)
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.unauthorized, "\(call)") {
                try await call.run(client, host: host)
            }
            #expect(await fake.receivedSpecs.count == 1, "\(call)")
        }
    }

    @Test(arguments: flavors)
    func forbidden403MapsToForbiddenWithoutRetry(flavor: DockerAPIFlavor) async {
        for call in ClientCall.networked(flavor) {
            let fake = FakeHTTPClient(.forbidden)
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.forbidden, "\(call)") {
                try await call.run(client, host: host)
            }
            #expect(await fake.receivedSpecs.count == 1, "\(call)")
        }
    }

    @Test(arguments: flavors)
    func timeoutMapsToUnreachable(flavor: DockerAPIFlavor) async {
        for call in ClientCall.networked(flavor) {
            let fake = FakeHTTPClient(.timeout)
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.unreachable, "\(call)") {
                try await call.run(client, host: host)
            }
        }
    }

    @Test(arguments: flavors)
    func unknownTransportErrorMapsToUnreachable(flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(.failure(URLError(.cannotFindHost)))
        let (client, host) = client(flavor, fake)
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await client.containers(on: host)
        }
    }

    @Test(arguments: flavors)
    func invalidJSONMapsToDecodingFailed(flavor: DockerAPIFlavor) async {
        for call in ClientCall.decoding(flavor) {
            let fake = FakeHTTPClient.json("<html><body>502 Bad Gateway</body></html>")
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.decodingFailed, "\(call)") {
                try await call.run(client, host: host)
            }
        }
    }

    @Test(arguments: flavors)
    func emptyBodyMapsToDecodingFailedForJSONEndpoints(flavor: DockerAPIFlavor) async {
        for call in ClientCall.decoding(flavor) {
            let fake = FakeHTTPClient.json("")
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.decodingFailed, "\(call)") {
                try await call.run(client, host: host)
            }
        }
    }

    @Test(arguments: flavors)
    func wrongJSONShapeMapsToDecodingFailed(flavor: DockerAPIFlavor) async {
        // An object where a list is expected.
        let fake = FakeHTTPClient.json(#"{"message":"ok"}"#)
        let (client, host) = client(flavor, fake)
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client.containers(on: host)
        }
    }

    @Test(arguments: flavors)
    func emptyLogsBodyReturnsNoLines(flavor: DockerAPIFlavor) async throws {
        let fake = FakeHTTPClient.json("")
        let (client, host) = client(flavor, fake)
        #expect(try await client.logs(on: host, containerID: "web").isEmpty)
    }

    @Test func engineCheckConnectionAcceptsEmptyBody() async throws {
        try await engineClient(FakeHTTPClient.json("")).checkConnection()
    }

    @Test(arguments: flavors)
    func serverErrorMapsToUnexpectedStatus(flavor: DockerAPIFlavor) async {
        for call in ClientCall.networked(flavor) {
            let fake = FakeHTTPClient(.serverError)
            let (client, host) = client(flavor, fake)
            await #expect(throws: ServiceProviderError.unexpectedStatus(500), "\(call)") {
                try await call.run(client, host: host)
            }
        }
        let logsFake = FakeHTTPClient(.serverError)
        let (client, host) = client(flavor, logsFake)
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await client.logs(on: host, containerID: "web")
        }
    }

    @Test(arguments: flavors)
    func notFoundContainerMapsToUnexpectedStatus404(flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient.json(#"{"message":"No such container: web"}"#, status: 404)
        let (client, host) = client(flavor, fake)
        await #expect(throws: ServiceProviderError.unexpectedStatus(404)) {
            _ = try await client.details(on: host, containerID: "web")
        }
    }

    @Test(arguments: flavors)
    func cancellationIsRethrownAsIs(flavor: DockerAPIFlavor) async {
        for call in ClientCall.networked(flavor) {
            let fake = FakeHTTPClient(.failure(CancellationError()))
            let (client, host) = client(flavor, fake)
            await #expect(throws: CancellationError.self, "\(call)") {
                try await call.run(client, host: host)
            }
        }
        let fake = FakeHTTPClient(.failure(CancellationError()))
        let (client, host) = client(flavor, fake)
        await #expect(throws: CancellationError.self) {
            _ = try await client.logs(on: host, containerID: "web")
        }
    }
}

// MARK: - URLProtocol that records any attempt to hit the network

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

final class RecordingURLProtocol: URLProtocol {
    static let startedCount = LockedCounter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.startedCount.increment()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
