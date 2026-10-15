import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import PatchNodeCore

// MARK: - Mock URLProtocol

/// Response returned by a stub handler for a given attempt.
enum StubResponse: Sendable {
    case http(status: Int, body: Data)
    case failure(URLError.Code)
}

/// Global, lock-protected registry. Each test uses a unique host so that stubs and
/// recorded requests never leak between tests, even if suites run in parallel.
final class StubRegistry: Sendable {
    static let shared = StubRegistry()

    private struct State {
        var handlers: [String: @Sendable (Int) -> StubResponse] = [:]
        var requests: [String: [URLRequest]] = [:]
    }

    private let state = Mutex(State())

    func register(host: String, handler: @escaping @Sendable (_ attempt: Int) -> StubResponse) {
        state.withLock {
            $0.handlers[host] = handler
            $0.requests[host] = []
        }
    }

    func unregister(host: String) {
        state.withLock {
            $0.handlers[host] = nil
            $0.requests[host] = nil
        }
    }

    /// Records the request and returns the stub for this attempt (1-based).
    func record(_ request: URLRequest) -> StubResponse? {
        guard let host = request.url?.host else { return nil }
        return state.withLock { state -> StubResponse? in
            guard let handler = state.handlers[host] else { return nil }
            state.requests[host, default: []].append(request)
            return handler(state.requests[host]?.count ?? 1)
        }
    }

    func requests(for host: String) -> [URLRequest] {
        state.withLock { $0.requests[host] ?? [] }
    }
}

final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = StubRegistry.shared.record(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch stub {
        case let .http(status, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// Unique, obviously fake host per test (reserved `.invalid` TLD).
private func uniqueHost() -> String {
    "pve-\(UUID().uuidString.lowercased()).example.invalid"
}

private let sampleJSON = Data(#"{"data":{"version":"8.2.4","release":"8.2"}}"#.utf8)

private func withStub(
    _ handler: @escaping @Sendable (_ attempt: Int) -> StubResponse,
    _ body: (_ host: String) async throws -> Void
) async rethrows {
    let host = uniqueHost()
    StubRegistry.shared.register(host: host, handler: handler)
    defer { StubRegistry.shared.unregister(host: host) }
    try await body(host)
}

// MARK: - HTTPClient tests

@Suite(.serialized)
struct HTTPClientTests {
    @Test func sendReturnsDataOn200() async throws {
        try await withStub({ _ in .http(status: 200, body: sampleJSON) }) { host in
            let client = HTTPClient(session: makeSession(), backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host):8006/api2/json/version")!)
            let (data, response) = try await client.send(spec)
            #expect(response.statusCode == 200)
            #expect(data == sampleJSON)
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func oversizedBodyIsRejectedWithoutRetry() async throws {
        let body = Data(repeating: UInt8(ascii: "a"), count: 4_097)
        await withStub({ _ in .http(status: 200, body: body) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0, maxResponseBytes: 4_096)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api/states")!)
            await #expect(throws: HTTPClientError.invalidResponse) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    /// A refused token stays a refused token (service paused), however big the page.
    @Test func oversized401IsStillUnauthorized() async throws {
        let body = Data(repeating: UInt8(ascii: "a"), count: 4_097)
        await withStub({ _ in .http(status: 401, body: body) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0, maxResponseBytes: 4_096)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api/states")!)
            await #expect(throws: HTTPClientError.unauthorized) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    /// Same for a 403 stopped while downloading: a refusal, not an invalid response.
    @Test func oversized403IsStillForbidden() async throws {
        let body = Data(repeating: UInt8(ascii: "a"), count: 4_097)
        await withStub({ _ in .http(status: 403, body: body) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0, maxResponseBytes: 4_096)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api/states")!)
            await #expect(throws: HTTPClientError.forbidden) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func bodyAtTheLimitIsAccepted() async throws {
        let body = Data(repeating: UInt8(ascii: "a"), count: 4_096)
        try await withStub({ _ in .http(status: 200, body: body) }) { host in
            let client = HTTPClient(session: makeSession(), backoff: 0, maxResponseBytes: 4_096)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api/states")!)
            let (data, _) = try await client.send(spec)
            #expect(data.count == 4_096)
        }
    }

    @Test func defaultLimitLeavesRoomForTheLargestLogs() {
        // 5000 Docker log lines of ~1 KB each, with their 8-byte frame headers.
        #expect(HTTPClient.defaultMaxResponseBytes > 5_000 * 1_032)
    }

    @Test func sendThrowsUnauthorizedOn401WithoutRetry() async throws {
        await withStub({ _ in .http(status: 401, body: Data(#"{"data":null}"#.utf8)) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!)
            await #expect(throws: HTTPClientError.unauthorized) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func sendThrowsBlockedByProxyOnHTML403WithoutRetry() async throws {
        let page = Data("<html><head><title>403 Forbidden</title></head><body>openresty</body></html>".utf8)
        await withStub({ _ in .http(status: 403, body: page) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!)
            await #expect(throws: HTTPClientError.blockedByProxy) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func sendThrowsForbiddenOn403WithoutRetry() async throws {
        await withStub({ _ in .http(status: 403, body: Data(#"{"data":null}"#.utf8)) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/nodes")!)
            await #expect(throws: HTTPClientError.forbidden) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func getRetriesAfterTimeoutAndSucceedsOnSecondAttempt() async throws {
        try await withStub({ attempt in
            attempt == 1 ? .failure(.timedOut) : .http(status: 200, body: sampleJSON)
        }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 2, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!)
            let (data, response) = try await client.send(spec)
            #expect(response.statusCode == 200)
            #expect(data == sampleJSON)
            #expect(StubRegistry.shared.requests(for: host).count == 2)
        }
    }

    @Test func getThrowsUnreachableAfterExhaustingMaxAttempts() async throws {
        await withStub({ _ in .failure(.cannotConnectToHost) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!)
            await #expect(throws: HTTPClientError.unreachable) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 3)
        }
    }

    @Test func postIsNeverRetriedOnRetryableError() async throws {
        await withStub({ attempt in
            attempt == 1 ? .failure(.timedOut) : .http(status: 200, body: sampleJSON)
        }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(
                method: .post,
                url: URL(string: "https://\(host)/api2/json/nodes/node-1/qemu/100/status/start")!,
                body: Data("{}".utf8)
            )
            await #expect(throws: HTTPClientError.unreachable) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func putIsNeverRetriedOnRetryableError() async throws {
        await withStub({ attempt in
            attempt == 1 ? .failure(.timedOut) : .http(status: 200, body: sampleJSON)
        }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .put, url: URL(string: "https://\(host)/api/stacks/3?endpointId=1")!, body: Data("{}".utf8))
            await #expect(throws: HTTPClientError.unreachable) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func onlyGetAllowsRetry() {
        #expect(HTTPRequestSpec.Method.get.allowsRetry)
        #expect(!HTTPRequestSpec.Method.post.allowsRetry)
        #expect(!HTTPRequestSpec.Method.put.allowsRetry)
    }

    @Test func postIsNotRetriedOn401() async throws {
        await withStub({ _ in .http(status: 401, body: Data()) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .post, url: URL(string: "https://\(host)/api/action")!)
            await #expect(throws: HTTPClientError.unauthorized) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func nonHTTPSURLIsRejectedBeforeAnyRequest() async throws {
        await withStub({ _ in .http(status: 200, body: sampleJSON) }) { host in
            let client = HTTPClient(session: makeSession(), backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "http://\(host)/api2/json/version")!)
            await #expect(throws: HTTPClientError.nonHTTPSURL) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).isEmpty)
        }
    }

    /// URLError.cancelled while this task isn't cancelled and its session wasn't
    /// replaced: the system dropped the request. Not the caller's cancellation (a
    /// store would discard nothing), not retried.
    @Test func foreignCancelledURLErrorIsUnreachableWithoutRetry() async throws {
        await withStub({ _ in .failure(.cancelled) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!)
            await #expect(throws: HTTPClientError.unreachable) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test(arguments: [URLError.Code.badServerResponse, .secureConnectionFailed])
    func nonRetryableURLErrorThrowsUnreachableAfterSingleAttempt(code: URLError.Code) async throws {
        await withStub({ _ in .failure(code) }) { host in
            let client = HTTPClient(session: makeSession(), maxAttempts: 3, backoff: 0)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!)
            await #expect(throws: HTTPClientError.unreachable) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }

    @Test func sentRequestCarriesHeadersMethodAndDefaultTimeout() async throws {
        try await withStub({ _ in .http(status: 200, body: sampleJSON) }) { host in
            let client = HTTPClient(session: makeSession(), backoff: 0)
            let spec = HTTPRequestSpec(
                method: .get,
                url: URL(string: "https://\(host)/api2/json/version")!,
                headers: [
                    "Authorization": "PVEAPIToken=fake-user@pam!fake=fake-token-123",
                    "Accept": "application/json",
                ]
            )
            _ = try await client.send(spec)
            let sent = try #require(StubRegistry.shared.requests(for: host).first)
            #expect(sent.httpMethod == "GET")
            #expect(sent.timeoutInterval == 10)
            #expect(sent.value(forHTTPHeaderField: "Authorization") == "PVEAPIToken=fake-user@pam!fake=fake-token-123")
            #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        }
    }
}

// MARK: - HTTPRequestSpec redaction tests

struct HTTPRequestSpecRedactionTests {
    @Test(arguments: ["Authorization", "X-API-Key", "X-Api-Key", "authorization", "x-api-key", "Proxy-Authorization", "Cookie", "X-Auth-Token"])
    func redactedDescriptionMasksSensitiveHeader(headerName: String) {
        let fakeToken = "fake-token-123"
        let spec = HTTPRequestSpec(
            method: .get,
            url: URL(string: "https://service.example.invalid/api/status")!,
            headers: [headerName: fakeToken, "Accept": "application/json"]
        )
        let description = spec.redactedDescription
        #expect(!description.contains(fakeToken))
        #expect(description.contains("\(headerName): <redacted>"))
        #expect(description.contains("Accept: application/json"))
        #expect(description.contains("GET https://service.example.invalid/api/status"))
    }

    @Test func redactedDescriptionMasksAllSensitiveHeadersTogether() {
        let spec = HTTPRequestSpec(
            method: .post,
            url: URL(string: "https://service.example.invalid/api/action")!,
            headers: [
                "Authorization": "Bearer fake-token-auth-111",
                "X-API-Key": "fake-token-apikey-222",
                "X-Api-Key": "fake-token-apikey-333",
                "User-Agent": "PatchNode-Tests",
            ]
        )
        let description = spec.redactedDescription
        #expect(!description.contains("fake-token-auth-111"))
        #expect(!description.contains("fake-token-apikey-222"))
        #expect(!description.contains("fake-token-apikey-333"))
        #expect(!description.contains("fake-token"))
        #expect(description.contains("<redacted>"))
        #expect(description.contains("User-Agent: PatchNode-Tests"))
        #expect(description.hasPrefix("POST "))
    }

    @Test func redactedDescriptionNeverIncludesBody() {
        let spec = HTTPRequestSpec(
            method: .post,
            url: URL(string: "https://service.example.invalid/api/login")!,
            body: Data(#"{"password":"fake-password-456"}"#.utf8)
        )
        #expect(!spec.redactedDescription.contains("fake-password-456"))
    }

    @Test func redactedDescriptionStripsURLUserInfoAndQueryValues() {
        let spec = HTTPRequestSpec(
            method: .get,
            url: URL(string: "https://u:secretpw@proxmox.example.invalid/api?token=abc123")!
        )
        let description = spec.redactedDescription
        #expect(!description.contains("secretpw"))
        #expect(!description.contains("abc123"))
        #expect(!description.contains("u:"))
        #expect(description.contains("proxmox.example.invalid"))
    }
}
