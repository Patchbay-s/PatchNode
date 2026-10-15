import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import DockerKit

private typealias F = DockerFixtures

private let actionPortainerHost = DockerHost(id: "portainer-1", name: "local", status: .up, portainerEndpointID: 1)
private let actionEngineHost = DockerHost.engine(name: "docker.example.invalid")

private func actionClient(_ flavor: DockerAPIFlavor, _ fake: FakeHTTPClient) -> (DockerClient, DockerHost) {
    switch flavor {
    case .portainer:
        return (DockerClient(flavor: .portainer, baseURL: F.portainerURL, credential: F.portainerKey, httpClient: fake),
                actionPortainerHost)
    case .engine:
        return (DockerClient(flavor: .engine, baseURL: F.engineURL, credential: F.engineCredential, httpClient: fake),
                actionEngineHost)
    }
}

private func expectedURL(_ flavor: DockerAPIFlavor, _ action: DockerContainerAction) -> String {
    switch flavor {
    case .portainer:
        return "https://portainer.example.invalid/api/endpoints/1/docker/containers/\(F.containerID)/\(action.rawValue)"
    case .engine:
        return "https://docker.example.invalid/containers/\(F.containerID)/\(action.rawValue)"
    }
}

private let actionFlavors: [DockerAPIFlavor] = [.portainer, .engine]

/// Docker Engine API error body (e.g. 404 "No such container", 500).
private func engineError(_ message: String, status: Int) -> FakeHTTPClient.Outcome {
    .json(#"{"message":"\#(message)"}"#, status: status)
}

@Suite("DockerClient.perform")
struct DockerActionTests {
    // MARK: Nominal

    @Test(arguments: actionFlavors, DockerContainerAction.allCases)
    func performPostsToContainerActionPathWithAuthAndNoBody(_ flavor: DockerAPIFlavor, _ action: DockerContainerAction) async throws {
        let fake = FakeHTTPClient(.response(status: 204, body: Data()))
        let (client, host) = actionClient(flavor, fake)

        let outcome = try await client.perform(action, on: host, containerID: F.containerID)

        #expect(outcome == .done)
        let specs = await fake.receivedSpecs
        #expect(specs.count == 1)
        let spec = try #require(specs.first)
        #expect(spec.method == .post)
        #expect(spec.url.absoluteString == expectedURL(flavor, action))
        #expect(spec.url.query == nil)
        #expect(spec.body == nil)
        switch flavor {
        case .portainer:
            #expect(spec.headers == ["X-API-Key": F.portainerKey])
        case .engine:
            #expect(spec.headers == ["Authorization": F.engineBasic])
        }
    }

    @Test(arguments: actionFlavors)
    func performReturnsDoneOn200(_ flavor: DockerAPIFlavor) async throws {
        let fake = FakeHTTPClient.json("", status: 200)
        let (client, host) = actionClient(flavor, fake)
        #expect(try await client.perform(.restart, on: host, containerID: F.containerID) == .done)
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors, [DockerContainerAction.start, .stop])
    func performReturnsAlreadyInStateOn304(_ flavor: DockerAPIFlavor, _ action: DockerContainerAction) async throws {
        let fake = FakeHTTPClient(.response(status: 304, body: Data()))
        let (client, host) = actionClient(flavor, fake)
        #expect(try await client.perform(action, on: host, containerID: F.containerID) == .alreadyInState)
        #expect(await fake.receivedSpecs.count == 1)
    }

    /// The action response body is never decoded: an HTML or truncated body on a
    /// success status must not turn a completed action into an error.
    @Test(arguments: actionFlavors, ["<html>OK</html>", "{\"message\":", ""])
    func performIgnoresBodyOnSuccess(_ flavor: DockerAPIFlavor, _ body: String) async throws {
        let fake = FakeHTTPClient.json(body, status: 204)
        let (client, host) = actionClient(flavor, fake)
        #expect(try await client.perform(.start, on: host, containerID: "test-app") == .done)
    }

    @Test(arguments: actionFlavors)
    func performAcceptsContainerName(_ flavor: DockerAPIFlavor) async throws {
        let fake = FakeHTTPClient(.response(status: 204, body: Data()))
        let (client, host) = actionClient(flavor, fake)
        _ = try await client.perform(.stop, on: host, containerID: "compose_web-1.a")
        #expect(await fake.receivedSpecs.first?.url.lastPathComponent == "stop")
        #expect(await fake.receivedSpecs.first?.url.path.hasSuffix("/containers/compose_web-1.a/stop") == true)
    }

    // MARK: Errors: exactly one request each (POST never retried)

    @Test(arguments: actionFlavors, DockerContainerAction.allCases)
    func performForbiddenMapsToForbiddenWithSingleRequest(_ flavor: DockerAPIFlavor, _ action: DockerContainerAction) async {
        // Socket proxy with POST=0 answers 403.
        let fake = FakeHTTPClient(.forbidden)
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await client.perform(action, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors)
    func performUnauthorizedMapsToUnauthorizedWithSingleRequest(_ flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(.unauthorized)
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await client.perform(.restart, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors)
    func performNotFoundMapsToUnexpectedStatus404WithSingleRequest(_ flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(engineError("No such container: \(F.containerID)", status: 404))
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.unexpectedStatus(404)) {
            _ = try await client.perform(.start, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors)
    func performServerErrorMapsToUnexpectedStatus500WithSingleRequest(_ flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(engineError(
            "driver failed programming external connectivity on endpoint web: Bind for 0.0.0.0:8080 failed: port is already allocated",
            status: 500
        ))
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await client.perform(.start, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors)
    func performTimeoutMapsToUnreachableWithSingleRequest(_ flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(.timeout)
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await client.perform(.stop, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors)
    func performRawURLErrorMapsToUnreachableWithSingleRequest(_ flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(.failure(URLError(.cannotConnectToHost)))
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await client.perform(.restart, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: actionFlavors)
    func performCancellationPropagates(_ flavor: DockerAPIFlavor) async {
        let fake = FakeHTTPClient(.failure(CancellationError()))
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: CancellationError.self) {
            _ = try await client.perform(.stop, on: host, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    // MARK: Validation before sending

    @Test(arguments: actionFlavors, ["", ".", "..", "../../images/prune", "abc/def", "abc?force=1", "web 01", "wéb", "abc%2Fdef"])
    func performRejectsInvalidContainerIDBeforeSending(_ flavor: DockerAPIFlavor, _ id: String) async {
        let fake = FakeHTTPClient(.response(status: 204, body: Data()))
        let (client, host) = actionClient(flavor, fake)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client.perform(.stop, on: host, containerID: id)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func portainerPerformRejectsHostWithoutEndpointBeforeSending() async {
        let fake = FakeHTTPClient(.response(status: 204, body: Data()))
        let client = DockerClient(flavor: .portainer, baseURL: F.portainerURL, credential: F.portainerKey, httpClient: fake)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client.perform(.start, on: actionEngineHost, containerID: F.containerID)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    // MARK: Logging

    @Test(arguments: actionFlavors)
    func performRequestRedactedDescriptionHidesCredential(_ flavor: DockerAPIFlavor) async throws {
        let fake = FakeHTTPClient(.response(status: 204, body: Data()))
        let (client, host) = actionClient(flavor, fake)
        _ = try await client.perform(.restart, on: host, containerID: F.containerID)
        let logged = try #require(await fake.receivedSpecs.first).redactedDescription

        #expect(logged.hasPrefix("POST "))
        #expect(logged.contains("<redacted>"))
        #expect(!logged.contains(F.portainerKey))
        #expect(!logged.contains("FAKE0000"))
        #expect(!logged.contains(F.engineBasic))
        #expect(!logged.contains("bW9uaXRvcjpmYWtlLXBhc3N3b3Jk"))
        #expect(!logged.contains("fake-password"))
    }
}

/// After a stop/restart POST timed out, the state is read back (GET only) instead
/// of sending the POST again.
@Suite("DockerClient.confirm")
struct DockerActionConfirmTests {
    private static let stoppedDetails = F.details.replacingOccurrences(of: #""Running": true"#, with: #""Running": false"#)

    @Test func stopIsConfirmedWhenContainerNoLongerRuns() async throws {
        let fake = FakeHTTPClient.json(Self.stoppedDetails)
        let (client, host) = actionClient(.engine, fake)
        let confirmed = try await client.confirm(.stop, on: host, containerID: F.containerID, since: .now, timeout: 10)
        #expect(confirmed)
        let specs = await fake.receivedSpecs
        #expect(specs.allSatisfy { $0.method == .get })
        #expect(specs.first?.url.path == "/containers/\(F.containerID)/json")
    }

    @Test func refusedReadStopsConfirmationAtOnce() async {
        let fake = FakeHTTPClient(.forbidden)
        let (client, host) = actionClient(.portainer, fake)
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await client.confirm(.restart, on: host, containerID: F.containerID, since: .now, timeout: 10)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func restartNeedsAStartAfterTheAction() async throws {
        // Fixture's StartedAt is in the past: not confirmed before the timeout.
        let fake = FakeHTTPClient.json(F.details)
        let (client, host) = actionClient(.engine, fake)
        let confirmed = try await client.confirm(.restart, on: host, containerID: F.containerID, since: .now, timeout: 2.5)
        #expect(!confirmed)
    }
}
