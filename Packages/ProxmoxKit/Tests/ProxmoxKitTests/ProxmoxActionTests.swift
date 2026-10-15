import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import ProxmoxKit

/// Realistic Proxmox VE 8 responses for power actions and task polling. Fake token,
/// `*.example.invalid` host.
private enum ActionFixtures {
    static let fakeToken = "test-user@pam!test-token=00000000-fake-0000-token"
    static let baseURL = URL(string: "https://proxmox.example.invalid:8006")!

    static let upid = "UPID:node-1:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:test-user@pam!test-token:"
    static let lxcUPID = "UPID:node-1:0000C0DF:0012D6B0:66F9A1C0:vzstart:200:test-user@pam!test-token:"

    /// POST /nodes/{node}/qemu/{vmid}/status/start
    static let actionResponse = #"{"data":"\#(upid)"}"#

    /// GET /nodes/{node}/tasks/{upid}/status while the task runs.
    static let running = #"""
    {"data":{"upid":"\#(upid)","node":"node-1","pid":49374,"pstart":1234595,"starttime":1727635890,
     "type":"qmstart","id":"100","user":"test-user@pam","tokenid":"test-token","status":"running"}}
    """#

    static func stopped(_ exitStatus: String) -> String {
        #"""
        {"data":{"upid":"\#(upid)","node":"node-1","pid":49374,"pstart":1234595,"starttime":1727635890,
         "type":"qmstart","id":"100","user":"test-user@pam","tokenid":"test-token","status":"stopped",
         "exitstatus":"\#(exitStatus)"}}
        """#
    }

    static func ok(_ json: String, status: Int = 200) -> FakeHTTPClient.Outcome {
        .response(status: status, body: Data(json.utf8))
    }

    static let serverError = ok(#"{"data":null,"errors":{"upid":"unable to read task"}}"#, status: 500)
}

private typealias AF = ActionFixtures

private func makeClient(_ fake: FakeHTTPClient) -> ProxmoxClient {
    ProxmoxClient(baseURL: AF.baseURL, apiTokenValue: AF.fakeToken, httpClient: fake)
}

private struct ActionCase: Sendable, CustomTestStringConvertible {
    let action: ProxmoxGuestAction
    let type: ProxmoxGuestType
    let vmid: Int
    var testDescription: String { "\(action.rawValue) \(type.rawValue)/\(vmid)" }

    static let all: [ActionCase] = ProxmoxGuestAction.allCases.flatMap { action in
        [ActionCase(action: action, type: .qemu, vmid: 100), ActionCase(action: action, type: .lxc, vmid: 200)]
    }
}

// MARK: - perform

@Suite("ProxmoxClient.perform")
struct ProxmoxPerformTests {
    @Test(arguments: ActionCase.all)
    fileprivate func performPostsToExactStatusPathAndReturnsUPID(_ c: ActionCase) async throws {
        let fake = FakeHTTPClient.json(AF.actionResponse)
        let upid = try await makeClient(fake).perform(c.action, node: "node-1", type: c.type, vmid: c.vmid)

        #expect(upid == AF.upid)
        let specs = await fake.receivedSpecs
        #expect(specs.count == 1)
        let spec = try #require(specs.first)
        #expect(spec.method == .post)
        #expect(spec.url.absoluteString
            == "https://proxmox.example.invalid:8006/api2/json/nodes/node-1/\(c.type.rawValue)/\(c.vmid)/status/\(c.action.rawValue)")
        #expect(spec.url.query == nil)
        #expect(spec.body == nil)
        #expect(spec.headers["Authorization"] == "PVEAPIToken=\(AF.fakeToken)")
    }

    @Test func performReturnsLXCTaskID() async throws {
        let fake = FakeHTTPClient.json(#"{"data":"\#(AF.lxcUPID)"}"#)
        let upid = try await makeClient(fake).perform(.start, node: "node-2", type: .lxc, vmid: 200)
        #expect(upid == AF.lxcUPID)
        #expect(await fake.receivedSpecs.first?.url.path == "/api2/json/nodes/node-2/lxc/200/status/start")
    }

    @Test func performForbiddenMapsToForbiddenWithSingleRequest() async {
        // PVEAuditor without PVEVMUser: the token reads but can't act.
        let fake = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await makeClient(fake).perform(.start, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performUnauthorizedMapsToUnauthorizedWithSingleRequest() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeClient(fake).perform(.shutdown, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performTimeoutMapsToUnreachableWithSingleRequest() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unreachable))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake).perform(.stop, node: "node-1", type: .lxc, vmid: 200)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performRawURLErrorTimeoutMapsToUnreachableWithSingleRequest() async {
        let fake = FakeHTTPClient(.failure(URLError(.timedOut)))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake).perform(.reboot, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performServerErrorMapsToUnexpectedStatusWithSingleRequest() async {
        let fake = FakeHTTPClient(AF.serverError)
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await makeClient(fake).perform(.start, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performInvalidJSONMapsToDecodingFailed() async {
        let fake = FakeHTTPClient.json("<html><body>502 Bad Gateway</body></html>")
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).perform(.start, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performEmptyBodyMapsToDecodingFailed() async {
        let fake = FakeHTTPClient.json("")
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).perform(.start, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func performNonStringDataMapsToDecodingFailed() async {
        let fake = FakeHTTPClient.json(#"{"data":42}"#)
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).perform(.start, node: "node-1", type: .qemu, vmid: 100)
        }
    }

    @Test(arguments: [
        #"{"data":null}"#,
        #"{}"#,
        #"{"data":""}"#,
        #"{"data":"OK"}"#,
        #"{"data":"upid:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:"}"#,
        #"{"data":"UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:/../../access/users"}"#,
        #"{"data":"UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:?x=1"}"#,
    ])
    func performWithoutUsableUPIDThrowsMissingTaskID(_ body: String) async {
        let fake = FakeHTTPClient.json(body)
        await #expect(throws: ProxmoxActionError.missingTaskID) {
            _ = try await makeClient(fake).perform(.start, node: "node-1", type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: ["", ".", "..", "../pve", "pve/qemu", "node-1?x=1", "pvé", "pve node"])
    func performRejectsInvalidNodeNameBeforeSending(_ node: String) async {
        let fake = FakeHTTPClient.json(AF.actionResponse)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).perform(.stop, node: node, type: .qemu, vmid: 100)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func performRequestRedactedDescriptionHidesToken() async throws {
        let fake = FakeHTTPClient.json(AF.actionResponse)
        _ = try await makeClient(fake).perform(.stop, node: "node-1", type: .qemu, vmid: 100)
        let spec = try #require(await fake.receivedSpecs.first)
        let logged = spec.redactedDescription
        #expect(!logged.contains("00000000-fake-0000-token"))
        #expect(!logged.contains(AF.fakeToken))
        #expect(logged.contains("Authorization: <redacted>"))
        #expect(logged.hasPrefix("POST "))
    }
}

// MARK: - UPID validation

@Suite("ProxmoxClient.isValidUPID")
struct ProxmoxUPIDValidationTests {
    @Test(arguments: [
        AF.upid,
        AF.lxcUPID,
        "UPID:node-2:00001234:0000ABCD:66F9A1B2:vzdump::root@pam:",
        "UPID:node.example.invalid:0000C0DE:0012D6A3:66F9A1B2:qmreboot:101:test-user@pam!fake-token:",
    ])
    func acceptsRealUPIDs(_ upid: String) {
        #expect(ProxmoxClient.isValidUPID(upid))
    }

    @Test(arguments: [
        "",
        "UPID",
        "upid:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:",
        "PID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:",
        "UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:/x",
        "UPID:pve/../..:qmstart:100:root@pam:",
        "UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:?q=1",
        "UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:#frag",
        "UPID:pve:0000C0DE:%2F:qmstart:100:root@pam:",
        "UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qm start:100:root@pam:",
        "UPID:pvé:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:",
        "UPID:pve:0000C0DE:0012D6A3:66F9A1B2:qmstart:100:root@pam:\n",
        "UPID:" + String(repeating: "a", count: 251),
    ])
    func rejectsMalformedUPIDs(_ upid: String) {
        #expect(!ProxmoxClient.isValidUPID(upid))
    }

    @Test func acceptsUPIDJustUnderLengthLimit() {
        #expect(ProxmoxClient.isValidUPID("UPID:" + String(repeating: "a", count: 250)))
    }
}

// MARK: - taskStatus

@Suite("ProxmoxClient.taskStatus")
struct ProxmoxTaskStatusTests {
    @Test func taskStatusUsesTaskPathWithUPIDAsSingleSegment() async throws {
        let fake = FakeHTTPClient.json(AF.running)
        _ = try await makeClient(fake).taskStatus(node: "node-1", upid: AF.upid)

        let specs = await fake.receivedSpecs
        #expect(specs.count == 1)
        let spec = try #require(specs.first)
        #expect(spec.method == .get)
        #expect(spec.url.path == "/api2/json/nodes/node-1/tasks/\(AF.upid)/status")
        #expect(spec.url.query == nil)
        #expect(spec.headers["Authorization"] == "PVEAPIToken=\(AF.fakeToken)")
        // ':' '!' '@' survive, and the UPID adds no path segment.
        let encodedPath = try #require(URLComponents(url: spec.url, resolvingAgainstBaseURL: false)?.percentEncodedPath)
        #expect(encodedPath.split(separator: "/").count == 7)
        #expect(!encodedPath.contains("%2F"))
        #expect(encodedPath.contains(AF.upid))
    }

    @Test func runningTaskDecodesAsRunningNotSucceeded() async throws {
        let status = try await makeClient(.json(AF.running)).taskStatus(node: "node-1", upid: AF.upid)
        #expect(status.isRunning)
        #expect(status.exitStatus == nil)
        #expect(!status.succeeded)
    }

    @Test(arguments: ["OK", "WARNINGS: 1"])
    func stoppedTaskWithOKOrWarningsSucceeded(_ exit: String) async throws {
        let status = try await makeClient(.json(AF.stopped(exit))).taskStatus(node: "node-1", upid: AF.upid)
        #expect(!status.isRunning)
        #expect(status.exitStatus == exit)
        #expect(status.succeeded)
    }

    @Test(arguments: [
        "start failed: QEMU exited with code 1",
        "can't lock file '/var/lock/qemu-server/lock-100.conf' - got timeout",
        "VM quit/powerdown failed - got timeout",
    ])
    func stoppedTaskWithErrorMessageDidNotSucceed(_ exit: String) async throws {
        let status = try await makeClient(.json(AF.stopped(exit))).taskStatus(node: "node-1", upid: AF.upid)
        #expect(!status.isRunning)
        #expect(status.exitStatus == exit)
        #expect(!status.succeeded)
    }

    @Test func stoppedTaskWithoutExitStatusDidNotSucceed() async throws {
        let json = #"{"data":{"upid":"\#(AF.upid)","node":"node-1","status":"stopped","exitstatus":""}}"#
        let status = try await makeClient(.json(json)).taskStatus(node: "node-1", upid: AF.upid)
        #expect(!status.isRunning)
        #expect(status.exitStatus == nil)
        #expect(!status.succeeded)
    }

    @Test(arguments: ["", "not-a-upid", "UPID:pve:../../x", "UPID:pve:0000C0DE:qmstart:100:root@pam:?a=b"])
    func invalidUPIDRejectedWithoutRequest(_ upid: String) async {
        let fake = FakeHTTPClient.json(AF.running)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).taskStatus(node: "node-1", upid: upid)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func invalidNodeRejectedWithoutRequest() async {
        let fake = FakeHTTPClient.json(AF.running)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).taskStatus(node: "../cluster", upid: AF.upid)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func nullDataMapsToInvalidResponse() async {
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(.json(#"{"data":null}"#)).taskStatus(node: "node-1", upid: AF.upid)
        }
    }

    @Test func invalidJSONMapsToDecodingFailed() async {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(.json("{\"data\":{")).taskStatus(node: "node-1", upid: AF.upid)
        }
    }

    @Test func unauthorizedMapsToUnauthorizedWithSingleRequest() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeClient(fake).taskStatus(node: "node-1", upid: AF.upid)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }
}

// MARK: - waitForTask
// waitForTask sleeps 1 s before the first poll, then 2 s, then 3 s: the tests below
// stay within ~3 s each and run in parallel.

@Suite("ProxmoxClient.waitForTask")
struct ProxmoxWaitForTaskTests {
    @Test func returnsWhenTaskIsStoppedOnFirstPoll() async throws {
        let fake = FakeHTTPClient.json(AF.stopped("OK"))
        let status = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        #expect(status.succeeded)
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func returnsFailedStatusWithoutThrowing() async throws {
        let fake = FakeHTTPClient.json(AF.stopped("start failed: QEMU exited with code 1"))
        let status = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        #expect(!status.isRunning)
        #expect(!status.succeeded)
    }

    @Test func pollsUntilTaskStops() async throws {
        let fake = FakeHTTPClient(sequence: [AF.ok(AF.running), AF.ok(AF.stopped("WARNINGS: 1"))])
        let status = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        #expect(status.succeeded)
        let specs = await fake.receivedSpecs
        #expect(specs.count == 2)
        #expect(specs.allSatisfy { $0.method == .get && $0.url.path.hasSuffix("/tasks/\(AF.upid)/status") })
    }

    @Test func transientServerErrorDoesNotAbortPolling() async throws {
        let fake = FakeHTTPClient(sequence: [AF.serverError, AF.ok(AF.stopped("OK"))])
        let status = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        #expect(status.succeeded)
        #expect(await fake.receivedSpecs.count == 2)
    }

    @Test func transientTimeoutDoesNotAbortPolling() async throws {
        let fake = FakeHTTPClient(sequence: [.failure(HTTPClientError.unreachable), AF.ok(AF.stopped("OK"))])
        let status = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        #expect(status.succeeded)
        #expect(await fake.receivedSpecs.count == 2)
    }

    @Test func timesOutWhileTaskStillRunning() async {
        let fake = FakeHTTPClient.json(AF.running)
        await #expect(throws: ProxmoxActionError.taskTimedOut(upid: AF.upid)) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 1.5)
        }
        #expect(await fake.receivedSpecs.count >= 1)
    }

    /// Out of time while the server kept answering 500: reported as a timeout.
    @Test func timeoutAfterTransientErrorsIsReportedAsTimeout() async {
        let fake = FakeHTTPClient(AF.serverError)
        await #expect(throws: ProxmoxActionError.taskTimedOut(upid: AF.upid)) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 1.5)
        }
    }

    @Test func invalidUPIDFailsImmediatelyWithoutRequest() async {
        let fake = FakeHTTPClient.json(AF.stopped("OK"))
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: "not-a-upid/x", timeout: 60)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func zeroTimeoutThrowsTaskTimedOutWithoutPolling() async {
        let fake = FakeHTTPClient.json(AF.stopped("OK"))
        await #expect(throws: ProxmoxActionError.taskTimedOut(upid: AF.upid)) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 0)
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func unauthorizedDuringPollingAbortsImmediately() async {
        let fake = FakeHTTPClient(sequence: [.failure(HTTPClientError.unauthorized), AF.ok(AF.stopped("OK"))])
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    /// CLAUDE.md: never retry on 401/403: a 403 ends the wait after one request.
    @Test func forbiddenDuringPollingAbortsImmediately() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 2.5)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func cancellationDuringSleepPropagatesWithoutRequest() async {
        let fake = FakeHTTPClient.json(AF.stopped("OK"))
        let client = makeClient(fake)
        let task = Task { try await client.waitForTask(node: "node-1", upid: AF.upid, timeout: 60) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func cancellationFromTransportIsNotTreatedAsTransient() async {
        let fake = FakeHTTPClient(sequence: [.failure(CancellationError()), AF.ok(AF.stopped("OK"))])
        await #expect(throws: CancellationError.self) {
            _ = try await makeClient(fake).waitForTask(node: "node-1", upid: AF.upid, timeout: 10)
        }
        #expect(await fake.receivedSpecs.count == 1)
    }
}
