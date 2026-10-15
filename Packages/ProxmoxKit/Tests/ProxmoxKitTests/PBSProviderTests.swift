import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import ProxmoxKit

private func makeProvider(_ fake: FakeHTTPClient, id: UUID = UUID(), displayName: String = "PBS test") -> PBSProvider {
    PBSProvider(id: id, displayName: displayName, baseURL: PBSFixtures.baseURL, apiTokenValue: PBSFixtures.fakeToken, httpClient: fake)
}

// MARK: - Identity

@Suite("PBSProvider identity")
struct PBSProviderIdentityTests {
    @Test func exposesIdKindAndDisplayName() {
        let id = UUID()
        let provider = makeProvider(FakeHTTPClient.json(PBSFixtures.datastoreList), id: id, displayName: "Sauvegardes")
        #expect(provider.id == id)
        #expect(provider.kind == .proxmoxBackupServer)
        #expect(provider.displayName == "Sauvegardes")
    }
}

// MARK: - healthCheck

@Suite("PBSProvider.healthCheck")
struct PBSProviderHealthCheckTests {
    @Test func healthCheckReturnsOkWhenDatastoreListSucceeds() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.datastoreList)
        let status = try await makeProvider(fake).healthCheck()
        guard case .ok = status else {
            Issue.record("Expected .ok, got \(status)")
            return
        }
        // Only the list: no per-store details for a connection test.
        let specs = await fake.receivedSpecs
        #expect(specs.map { $0.url.path(percentEncoded: false) } == ["/api2/json/admin/datastore"])
        #expect(specs.first?.headers["Authorization"] == "PBSAPIToken=\(PBSFixtures.fakeToken)")
    }

    @Test func healthCheckReturnsOkWithNoDatastore() async throws {
        let status = try await makeProvider(FakeHTTPClient.json(#"{"data":[]}"#)).healthCheck()
        guard case .ok = status else {
            Issue.record("Expected .ok, got \(status)")
            return
        }
    }

    @Test func healthCheckReturnsUnauthorizedOn401WithoutRetry() async throws {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        let status = try await makeProvider(fake).healthCheck()
        guard case .unauthorized = status else {
            Issue.record("Expected .unauthorized, got \(status)")
            return
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func healthCheckReturnsUnauthorizedOn403WithoutRetry() async throws {
        let fake = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        let status = try await makeProvider(fake).healthCheck()
        guard case .unauthorized = status else {
            Issue.record("Expected .unauthorized, got \(status)")
            return
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func healthCheckReturnsDegradedWithStatusOnUnexpectedHTTPStatus() async throws {
        let status = try await makeProvider(FakeHTTPClient.json(#"{"data":null}"#, status: 500)).healthCheck()
        guard case .degraded(let reason) = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
        #expect(reason == "HTTP 500")
    }

    @Test(arguments: ["<html>not json</html>", "", #"{"data":"nope"}"#])
    func healthCheckReturnsDegradedOnInvalidJSON(body: String) async throws {
        let status = try await makeProvider(FakeHTTPClient.json(body)).healthCheck()
        guard case .degraded(let reason) = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
        #expect(reason == "invalid response")
    }

    @Test func healthCheckReturnsDegradedOnInvalidTransportResponse() async throws {
        let status = try await makeProvider(FakeHTTPClient(.failure(HTTPClientError.invalidResponse))).healthCheck()
        guard case .degraded = status else {
            Issue.record("Expected .degraded, got \(status)")
            return
        }
    }

    @Test(arguments: [
        HTTPClientError.unreachable,
        HTTPClientError.nonHTTPSURL,
    ])
    func healthCheckReturnsUnreachableOnTransportFailure(error: HTTPClientError) async throws {
        let fake = FakeHTTPClient(.failure(error))
        let status = try await makeProvider(fake).healthCheck()
        guard case .unreachable(let underlying) = status else {
            Issue.record("Expected .unreachable, got \(status)")
            return
        }
        #expect(underlying as? ProxmoxProviderError == .unreachable)
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func healthCheckReturnsUnreachableOnRawTimeout() async throws {
        let status = try await makeProvider(FakeHTTPClient(.failure(URLError(.timedOut)))).healthCheck()
        guard case .unreachable = status else {
            Issue.record("Expected .unreachable, got \(status)")
            return
        }
    }

    @Test func healthCheckRethrowsCancellation() async {
        await #expect(throws: CancellationError.self) {
            _ = try await makeProvider(FakeHTTPClient(.failure(CancellationError()))).healthCheck()
        }
    }
}

// MARK: - loadSnapshot / summary

@Suite("PBSProvider snapshot and summary")
struct PBSProviderSnapshotTests {
    @Test func loadSnapshotFetchesDatastoresThenTasks() async throws {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence + [PBSFixtures.response(PBSFixtures.tasks)])
        let provider = makeProvider(fake, displayName: "PBS home")
        let snapshot = try await PBSProvider.loadSnapshot(client: provider.client, serviceID: provider.id, serviceName: "PBS home")
        #expect(snapshot.serviceID == provider.id)
        #expect(snapshot.serviceName == "PBS home")
        #expect(snapshot.datastores.map(\.name) == ["backup-main", "offsite"])
        #expect(snapshot.tasks.count == 3)
        let last = try #require(await fake.receivedSpecs.last)
        #expect(last.url.path(percentEncoded: false) == "/api2/json/nodes/localhost/tasks")
    }

    @Test func tasksFailureKeepsDatastores() async throws {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence + [.failure(HTTPClientError.forbidden)])
        let provider = makeProvider(fake)
        let snapshot = try await PBSProvider.loadSnapshot(client: provider.client, serviceID: provider.id, serviceName: "PBS")
        #expect(snapshot.datastores.count == 2)
        #expect(snapshot.tasks.isEmpty)
        #expect(await fake.receivedSpecs.count == 6)
    }

    @Test func datastoreListFailureFailsTheSnapshotWithoutFurtherRequests() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        let provider = makeProvider(fake)
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await PBSProvider.loadSnapshot(client: provider.client, serviceID: provider.id, serviceName: "PBS")
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func cancellationDuringTasksIsRethrown() async {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence + [.failure(CancellationError())])
        let provider = makeProvider(fake)
        await #expect(throws: CancellationError.self) {
            _ = try await PBSProvider.loadSnapshot(client: provider.client, serviceID: provider.id, serviceName: "PBS")
        }
    }

    @Test func summaryReportsDatastoreCounts() async throws {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence + [PBSFixtures.response(#"{"data":[]}"#)])
        let summary = try await makeProvider(fake).summary()
        #expect(summary.headline == "2")
        #expect(summary.details["datastores"] == "2")
        // backup-main is at 90 %.
        #expect(summary.details["datastoresAboveThreshold"] == "1")
        #expect(summary.details["failedTasks24h"] == "0")
        #expect(summary.details["staleBackups"] != nil)
    }

    @Test func summaryPropagatesUnauthorized() async {
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeProvider(FakeHTTPClient(.failure(HTTPClientError.unauthorized))).summary()
        }
    }
}
