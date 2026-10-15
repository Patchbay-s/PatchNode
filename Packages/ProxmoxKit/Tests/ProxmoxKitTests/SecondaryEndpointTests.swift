import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import ProxmoxKit

// Only /cluster/resources decides the service's state; /cluster/tasks is a
// secondary part whose failure must neither fail nor pause the service.

private let baseURL = URL(string: "https://proxmox.example.invalid:8006")!
private let token = "test-user@pam!test-token=00000000-fake-0000-token"
private let resources = Data(#"{"data":[{"id":"node/node-1","type":"node","node":"node-1","status":"online","maxcpu":8,"maxmem":34359738368},{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"status":"running"}]}"#.utf8)
private let tasks = Data(#"{"data":[{"upid":"UPID:pve:00001234:00ABCDEF:65000000:qmstart:100:root@pam:","node":"node-1","type":"qmstart","id":"100","user":"root@pam","starttime":1700000000,"endtime":1700000005,"status":"OK"}]}"#.utf8)
private let forbiddenJSON = Data(#"{"data":null,"message":"Permission check failed (/, Sys.Audit)"}"#.utf8)

struct SecondaryEndpointTests {
    @Test func firstRefreshOKThen403JSONOnTasksKeepsTheServiceUp() async throws {
        let fake = FakeHTTPClient(sequence: [
            .response(status: 200, body: resources), .response(status: 200, body: tasks),
            .response(status: 200, body: resources), .response(status: 403, body: forbiddenJSON),
        ])
        let client = ProxmoxClient(baseURL: baseURL, apiTokenValue: token, httpClient: fake)
        let id = UUID()
        var pauses = ServicePauses()

        let first = try await ProxmoxServiceSnapshot.load(serviceID: id, serviceName: "Test Site A", client: client)
        #expect(first.tasks.count == 1)
        #expect(!first.tasksUnavailable)
        pauses.recordSuccess(id)

        // Second refresh: the task list is refused with a JSON 403 (service's
        // own refusal). The snapshot still loads: no error, no pause.
        let second = try await ProxmoxServiceSnapshot.load(serviceID: id, serviceName: "Test Site A", client: client)
        pauses.recordSuccess(id)
        #expect(second.resources.count == 2)
        #expect(second.tasks.isEmpty)
        #expect(second.tasksUnavailable)
        #expect(!pauses.isPaused(id, at: .now))

        let inventory = ProxmoxInventory(snapshots: [second])
        #expect(inventory.tasksUnavailableServiceIDs == [id])
        #expect(inventory.guests.count == 1)
        #expect(await fake.receivedSpecs.map(\.url.path) == [
            "/api2/json/cluster/resources", "/api2/json/cluster/tasks",
            "/api2/json/cluster/resources", "/api2/json/cluster/tasks",
        ])
    }

    @Test(arguments: [
        FakeHTTPClient.Outcome.response(status: 500, body: Data()),
        .failure(HTTPClientError.unreachable),
        .failure(HTTPClientError.blockedByProxy),
        .failure(HTTPClientError.unauthorized),
    ])
    func anyTasksErrorOnlyMarksTasksUnavailable(_ tasksOutcome: FakeHTTPClient.Outcome) async throws {
        let fake = FakeHTTPClient(sequence: [.response(status: 200, body: resources), tasksOutcome])
        let client = ProxmoxClient(baseURL: baseURL, apiTokenValue: token, httpClient: fake)
        let snapshot = try await ProxmoxServiceSnapshot.load(serviceID: UUID(), serviceName: "node-1", client: client)
        #expect(snapshot.tasksUnavailable)
        #expect(snapshot.resources.count == 2)
    }

    @Test func primaryEndpointErrorIsTheServiceState() async throws {
        let fake = FakeHTTPClient(.failure(HTTPClientError.blockedByProxy))
        let client = ProxmoxClient(baseURL: baseURL, apiTokenValue: token, httpClient: fake)
        await #expect(throws: ServiceProviderError.blockedByProxy) {
            _ = try await ProxmoxServiceSnapshot.load(serviceID: UUID(), serviceName: "node-1", client: client)
        }
        // Nothing else is asked once the primary endpoint failed.
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func slowTaskListIsCutOffWithoutFailingTheService() async throws {
        let client = ProxmoxClient(baseURL: baseURL, apiTokenValue: token, httpClient: SlowTasksClient())
        let snapshot = try await ProxmoxServiceSnapshot.load(serviceID: UUID(), serviceName: "node-1", client: client, tasksTimeout: 0.05)
        #expect(snapshot.tasksUnavailable)
        #expect(snapshot.resources.count == 2)
    }
}

/// Answers /cluster/resources at once and never answers /cluster/tasks.
private struct SlowTasksClient: HTTPClientProtocol {
    func send(_ request: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
        if request.url.path.hasSuffix("/cluster/tasks") {
            try await Task.sleep(for: .seconds(30))
        }
        let response = HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (resources, response)
    }
}
