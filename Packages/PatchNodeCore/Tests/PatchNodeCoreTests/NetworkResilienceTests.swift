import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import PatchNodeCore

// Bug seen on iPhone: two Proxmox hosts behind one NPM (same IP, wildcard
// certificate) failing at random during automatic refreshes. These tests cover
// the 421 retry on a new connection, the proxy pause with automatic resume, and
// the request log.

private func stubConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return configuration
}

/// Counts the sessions it creates, to see that a retry went to a new one.
private final class SessionCounter: Sendable {
    private let count = Mutex(0)
    var made: Int { count.withLock { $0 } }

    func make() -> URLSession {
        count.withLock { $0 += 1 }
        return URLSession(configuration: stubConfiguration())
    }
}

private func uniqueHost() -> String {
    "npm-\(UUID().uuidString.lowercased()).example.invalid"
}

private let resourcesJSON = Data(#"{"data":[]}"#.utf8)
private let proxyPage = Data("<html><head><title>403 Forbidden</title></head><body>openresty</body></html>".utf8)

private func withStub(
    _ handler: @escaping @Sendable (_ attempt: Int) -> StubResponse,
    _ body: (_ host: String) async throws -> Void
) async rethrows {
    let host = uniqueHost()
    StubRegistry.shared.register(host: host, handler: handler)
    defer { StubRegistry.shared.unregister(host: host) }
    try await body(host)
}

@Suite(.serialized)
struct MisdirectedRequestTests {
    @Test func firstRefreshOKThen421IsRetriedOnceOnANewSession() async throws {
        let counter = SessionCounter()
        let log = RequestLog()
        let label = RequestLog.Label(serviceID: UUID(), serviceName: "Test Site A")
        // 1: first refresh OK; 2: 421 on the reused connection; 3: OK on the new one.
        try await withStub({ attempt in
            attempt == 2 ? .http(status: 421, body: Data()) : .http(status: 200, body: resourcesJSON)
        }) { host in
            let client = HTTPClient(sessions: RenewableSession(make: counter.make), backoff: 0, label: label, log: log)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/cluster/resources")!)

            _ = try await client.fetchOK(spec)
            #expect(counter.made == 1)

            let data = try await client.fetchOK(spec)
            #expect(data == resourcesJSON)
            #expect(StubRegistry.shared.requests(for: host).count == 3)
            #expect(counter.made == 2, "the retry must use a new session (new connection pool)")
        }
        let requests = log.entries().compactMap { entry -> RequestLog.Request? in
            if case .request(let request) = entry.kind { return request }
            return nil
        }
        #expect(requests.map(\.outcome) == [.ok, .misdirected, .ok])
        #expect(requests.map(\.freshConnection) == [false, false, true])
        #expect(log.entries().allSatisfy { $0.serviceName == "Test Site A" })
    }

    @Test func repeated421IsNeitherARefusalNorAPause() async throws {
        let counter = SessionCounter()
        await withStub({ _ in .http(status: 421, body: Data()) }) { host in
            let client = HTTPClient(sessions: RenewableSession(make: counter.make), backoff: 0, label: nil, log: nil)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/cluster/resources")!)
            do {
                _ = try await client.fetchOK(spec)
                Issue.record("expected an error")
            } catch {
                #expect(error as? ServiceProviderError == .unexpectedStatus(421))
                #expect(PauseReason(error: error) == nil)
                var pauses = ServicePauses()
                let id = UUID()
                let pause = pauses.recordFailure(id, error: error, at: .now)
                #expect(pause == nil)
                #expect(!pauses.isPaused(id, at: .now))
            }
            // One retry only.
            #expect(StubRegistry.shared.requests(for: host).count == 2)
        }
    }

    @Test func postGetting421IsNeverResent() async throws {
        let counter = SessionCounter()
        try await withStub({ _ in .http(status: 421, body: Data()) }) { host in
            let client = HTTPClient(sessions: RenewableSession(make: counter.make), backoff: 0, label: nil, log: nil)
            let spec = HTTPRequestSpec(method: .post, url: URL(string: "https://\(host)/api2/json/nodes/node-1/qemu/100/status/reboot")!)
            let (_, response) = try await client.send(spec)
            #expect(response.statusCode == 421)
            #expect(StubRegistry.shared.requests(for: host).count == 1)
            // The next action starts on a new connection.
            #expect(counter.made == 2)
        }
    }

    @Test func timeoutRetryGoesToANewSession() async throws {
        let counter = SessionCounter()
        try await withStub({ attempt in
            attempt == 1 ? .failure(.timedOut) : .http(status: 200, body: resourcesJSON)
        }) { host in
            let client = HTTPClient(sessions: RenewableSession(make: counter.make), backoff: 0, label: nil, log: nil)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/cluster/resources")!)
            _ = try await client.fetchOK(spec)
            #expect(StubRegistry.shared.requests(for: host).count == 2)
            #expect(counter.made == 2)
        }
    }
}

@Suite(.serialized)
struct ProxyPauseTests {
    @Test func proxy403ThenOKResumesAutomatically() async throws {
        let id = UUID()
        var pauses = ServicePauses()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try await withStub({ attempt in
            attempt == 1 ? .http(status: 403, body: proxyPage) : .http(status: 200, body: resourcesJSON)
        }) { host in
            let client = HTTPClient(sessions: RenewableSession { URLSession(configuration: stubConfiguration()) }, backoff: 0, label: nil, log: nil)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/cluster/resources")!)

            // Refresh at t0: the proxy refuses.
            do {
                _ = try await client.fetchOK(spec)
                Issue.record("expected blockedByProxy")
            } catch {
                #expect(error as? ServiceProviderError == .blockedByProxy)
                let pause = pauses.recordFailure(id, error: error, at: t0)
                #expect(pause?.reason == .proxyBlocked)
                #expect(pause?.resumeAt == t0.addingTimeInterval(30))
            }
            // Refresh at t0 + 10 s: still paused, nothing sent.
            #expect(pauses.isPaused(id, at: t0.addingTimeInterval(10)))
            #expect(StubRegistry.shared.requests(for: host).count == 1)

            // Refresh at t0 + 30 s: automatic resume, the probe succeeds.
            let now = t0.addingTimeInterval(30)
            #expect(!pauses.isPaused(id, at: now))
            #expect(pauses.isResumeProbe(id, at: now))
            _ = try await client.fetchOK(spec)
            let ended = pauses.recordSuccess(id)
            #expect(ended)
            #expect(pauses.pause(for: id) == nil)
            #expect(StubRegistry.shared.requests(for: host).count == 2)
        }
    }

    @Test func proxyBackoffIsCappedAtTwoMinutes() {
        let id = UUID()
        var pauses = ServicePauses()
        var now = Date(timeIntervalSince1970: 0)
        var delays: [TimeInterval] = []
        for _ in 0..<5 {
            let pause = pauses.recordFailure(id, error: ServiceProviderError.blockedByProxy, at: now)
            let resumeAt = try! #require(pause?.resumeAt)
            delays.append(resumeAt.timeIntervalSince(now))
            now = resumeAt
        }
        #expect(delays == [30, 60, 120, 120, 120])
        #expect(pauses.nextResume == now)
    }

    @Test func tokenRefusalWaitsForPullToRefresh() {
        let id = UUID()
        var pauses = ServicePauses()
        let now = Date.now
        let pause = pauses.recordFailure(id, error: ServiceProviderError.unauthorized, at: now)
        #expect(pause?.reason == .tokenRejected)
        #expect(pause?.resumeAt == nil)
        #expect(pauses.isPaused(id, at: now.addingTimeInterval(3600)))
        #expect(!pauses.isResumeProbe(id, at: now.addingTimeInterval(3600)))
        // A network change lifts proxy pauses only.
        let proxyOnly = pauses.resume(reasons: [.proxyBlocked])
        #expect(proxyOnly.isEmpty)
        #expect(pauses.isPaused(id, at: now))
        let all = pauses.resume(reasons: [.proxyBlocked, .tokenRejected])
        #expect(all == [id])
    }

    @Test func networkChangeLiftsProxyPause() {
        let id = UUID()
        var pauses = ServicePauses()
        pauses.recordFailure(id, error: ServiceProviderError.blockedByProxy, at: .now)
        let resumed = pauses.resume(reasons: [.proxyBlocked])
        #expect(resumed == [id])
        #expect(!pauses.isPaused(id, at: .now))
    }

    @Test func probeFailingOtherwiseEndsTheAutomaticPause() {
        let id = UUID()
        var pauses = ServicePauses()
        let t0 = Date.now
        pauses.recordFailure(id, error: ServiceProviderError.blockedByProxy, at: t0)
        let pause = pauses.recordFailure(id, error: ServiceProviderError.unreachable, at: t0.addingTimeInterval(30))
        #expect(pause == nil)
        #expect(pauses.pause(for: id) == nil)
    }

    @Test func serviceForbiddenIsATokenRefusal() {
        #expect(PauseReason(error: ServiceProviderError.forbidden) == .tokenRejected)
        #expect(PauseReason(error: ServiceProviderError.unexpectedStatus(500)) == nil)
        #expect(PauseReason(error: TimeoutError()) == nil)
    }
}

@Suite(.serialized)
struct RequestLogTests {
    @Test func keepsTheLastEntriesOnly() {
        let log = RequestLog(capacity: 3)
        for index in 0..<5 {
            log.append(.event(.resumed(.succeeded)), label: RequestLog.Label(serviceID: UUID(), serviceName: "s\(index)"))
        }
        #expect(log.entries().map(\.serviceName) == ["s2", "s3", "s4"])
        let version = log.version
        log.clear()
        #expect(log.version != version)
        #expect(log.entries().isEmpty)
    }

    @Test func pathKeepsQueryNamesButNotValues() {
        let url = URL(string: "https://proxmox.example.invalid/api2/json/nodes/node-1/qemu/100/rrddata?timeframe=hour&cf=AVERAGE&token=fake-query-value")!
        let path = RequestLog.loggedPath(url)
        #expect(path == "/api2/json/nodes/node-1/qemu/100/rrddata?timeframe&cf&token")
        #expect(!path.contains("fake-query-value"))
        #expect(!path.contains("example.invalid"))
    }

    @Test func pathLeavesOutTheServiceBasePath() {
        let base = URL(string: "https://proxy.example.invalid/private-prefix/")!
        let basePath = RequestLog.Label(serviceID: UUID(), serviceName: "Proxmox test", baseURL: base).basePath
        #expect(basePath == "/private-prefix")
        let url = URL(string: "https://proxy.example.invalid/private-prefix/api2/json/cluster/resources?type=vm")!
        #expect(RequestLog.loggedPath(url, basePath: basePath) == "/api2/json/cluster/resources?type")
        #expect(RequestLog.loggedPath(URL(string: "https://proxy.example.invalid/private-prefix")!, basePath: basePath) == "/")
        let outside = RequestLog.loggedPath(URL(string: "https://proxy.example.invalid/other/secret-dir/login")!, basePath: basePath)
        #expect(outside == "…/login")
        #expect(RequestLog.Label(serviceID: UUID(), serviceName: "Proxmox test", baseURL: URL(string: "https://proxmox.example.invalid:8006")!).basePath == "")
    }

    @Test func logNeverContainsCredentialsOrBody() async throws {
        let log = RequestLog()
        let secret = "test-user@pam!fake-token=not-a-real-secret"
        let body = Data(#"{"data":[{"secret-in-body":true}]}"#.utf8)
        try await withStub({ _ in .http(status: 200, body: body) }) { host in
            let client = HTTPClient(
                sessions: RenewableSession { URLSession(configuration: stubConfiguration()) }, backoff: 0,
                label: RequestLog.Label(serviceID: UUID(), serviceName: "node-1"), log: log
            )
            let spec = HTTPRequestSpec(
                method: .get, url: URL(string: "https://user:pw@\(host)/api2/json/version?password=pw")!,
                headers: ["Authorization": "PVEAPIToken=\(secret)", "X-API-Key": "k3y"]
            )
            _ = try await client.send(spec)
            let text = log.exportText()
            #expect(text.contains("GET /api2/json/version?password"))
            #expect(text.contains("HTTP 200"))
            for leaked in [secret, "PVEAPIToken", "k3y", "secret-in-body", host, "user:pw", "=pw"] {
                #expect(!text.contains(leaked), "log leaks \(leaked)")
            }
        }
    }

    @Test func headerValuesAreShortAndClean() {
        #expect(RequestLog.loggedHeader("nginx\r\nX-Evil: 1") == "nginxX-Evil: 1")
        #expect(RequestLog.loggedHeader(String(repeating: "a", count: 200))?.count == 80)
        #expect(RequestLog.loggedHeader(nil) == nil)
    }
}

@Suite(.serialized)
struct SessionLifecycleTests {
    @Test func timeoutBetweenTwoProxyRefusalsKeepsTheBackoff() {
        let id = UUID()
        var pauses = ServicePauses()
        let t0 = Date(timeIntervalSince1970: 0)
        pauses.recordFailure(id, error: ServiceProviderError.blockedByProxy, at: t0)
        // The probe at +30 s times out: the pause ends, the count stays.
        pauses.recordFailure(id, error: ServiceProviderError.unreachable, at: t0.addingTimeInterval(30))
        #expect(pauses.pause(for: id) == nil)
        let next = pauses.recordFailure(id, error: ServiceProviderError.blockedByProxy, at: t0.addingTimeInterval(40))
        #expect(next?.strikes == 2)
        #expect(next?.resumeAt == t0.addingTimeInterval(100))
        // An answer resets it.
        pauses.recordSuccess(id)
        let fresh = pauses.recordFailure(id, error: ServiceProviderError.blockedByProxy, at: t0.addingTimeInterval(200))
        #expect(fresh?.strikes == 1)
    }

    @Test func removedServiceFailsCleanlyWithoutStartingARequest() async throws {
        await withStub({ _ in .http(status: 200, body: resourcesJSON) }) { host in
            let sessions = RenewableSession { URLSession(configuration: stubConfiguration()) }
            let client = HTTPClient(sessions: sessions, backoff: 0, label: nil, log: nil)
            sessions.invalidate()
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/cluster/resources")!)
            await #expect(throws: CancellationError.self) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).isEmpty)
            // Renewing a closed session creates nothing.
            let before = sessions.current
            sessions.renew(replacing: before)
            #expect(sessions.current === before)
        }
    }

    @Test func poolRemovalClosesOnlyThatService() {
        let pool = HTTPSessionPool(log: nil) { URLSession(configuration: stubConfiguration()) }
        let a = UUID(), b = UUID()
        let sessionA = pool.session(for: a)
        let sessionB = pool.session(for: b)
        pool.remove([a])
        #expect(sessionA.isClosed)
        #expect(!sessionB.isClosed)
        #expect(pool.session(for: a) !== sessionA, "a re-added service starts on a new session")
    }

    @Test func eachServiceHasItsOwnSession() {
        let pool = HTTPSessionPool(log: nil) { URLSession(configuration: stubConfiguration()) }
        let a = UUID(), b = UUID()
        #expect(pool.session(for: a) === pool.session(for: a))
        #expect(pool.session(for: a).current !== pool.session(for: b).current)
    }
}

@Suite(.serialized)
struct NetworkResetTests {
    /// Network path changed while a GET was in flight: `resetAll` cancels it; it
    /// goes again once on the new session instead of failing the service.
    @Test func getCancelledByASessionResetIsSentAgainOnTheNewSession() async throws {
        let counter = SessionCounter()
        let sessions = RenewableSession(make: counter.make)
        try await withStub({ attempt in
            if attempt == 1 {
                // Swap the session as reset() does; the stub reports the
                // cancellation itself (cancelling from inside startLoading
                // crashes swift-corelibs-foundation on Linux).
                sessions.renew(replacing: sessions.current)
                return .failure(.cancelled)
            }
            return .http(status: 200, body: resourcesJSON)
        }) { host in
            let client = HTTPClient(sessions: sessions, backoff: 0, label: nil, log: nil)
            let spec = HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/cluster/resources")!)
            let data = try await client.fetchOK(spec)
            #expect(data == resourcesJSON)
            #expect(StubRegistry.shared.requests(for: host).count == 2)
            #expect(counter.made == 2)
        }
    }

    /// An idle service costs nothing on a network change: its session is
    /// replaced by its next request, not at once.
    @Test func idleSessionIsReplacedByItsNextRequestOnly() async throws {
        let counter = SessionCounter()
        let pool = HTTPSessionPool(log: nil, make: counter.make)
        let id = UUID()
        let sessions = pool.session(for: id)
        let first = sessions.current
        pool.resetAll()
        #expect(counter.made == 1)
        #expect(sessions.isStale)
        #expect(sessions.current === first)
        try await withStub({ _ in .http(status: 200, body: resourcesJSON) }) { host in
            let client = HTTPClient(sessions: sessions, backoff: 0, label: nil, log: nil)
            _ = try await client.fetchOK(HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!))
            #expect(counter.made == 2)
            #expect(sessions.current !== first)
            #expect(!sessions.isStale)
            _ = try await client.fetchOK(HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api2/json/version")!))
            #expect(counter.made == 2)
        }
    }

    @Test func postCancelledByASessionResetIsNotResent() async throws {
        let sessions = RenewableSession { URLSession(configuration: stubConfiguration()) }
        await withStub({ _ in
            sessions.renew(replacing: sessions.current)
            return .failure(.cancelled)
        }) { host in
            let client = HTTPClient(sessions: sessions, backoff: 0, label: nil, log: nil)
            let spec = HTTPRequestSpec(method: .post, url: URL(string: "https://\(host)/api2/json/nodes/node-1/qemu/100/status/reboot")!)
            await #expect(throws: HTTPClientError.unreachable) {
                _ = try await client.send(spec)
            }
            #expect(StubRegistry.shared.requests(for: host).count == 1)
        }
    }
}
