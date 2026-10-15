import Foundation
#if canImport(Security)
import Security
#endif
import Synchronization
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

public enum HTTPClientError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case unreachable
    case invalidResponse
    case nonHTTPSURL
    /// 403 page served by a reverse proxy (HTML), not by the service: typically an
    /// NPM "LAN only" Access List while the VPN is off.
    case blockedByProxy
}

public protocol HTTPClientProtocol: Sendable {
    func send(_ request: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse)
}

/// Stateless (only `let`s), so a plain Sendable class: no actor hop per request.
public final class HTTPClient: HTTPClientProtocol, Sendable {
    private let sessions: RenewableSession
    private let timeout: TimeInterval
    private let maxAttempts: Int
    private let backoff: TimeInterval
    private let maxResponseBytes: Int
    private let label: RequestLog.Label?
    private let log: RequestLog?
    #if canImport(os)
    private static let logger = Logger(subsystem: "fr.antxis.apple.labwatch", category: "http")
    #endif

    /// Dedicated session: bounded total duration (the per-request timeout only covers
    /// idle time) and no cache, so authenticated responses never land in Cache.db.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        // Demo mode: `*.patchnode-demo.invalid` is answered on the device; every
        // other host goes to the network as usual.
        configuration.protocolClasses = [DemoURLProtocol.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration, delegate: SameOriginRedirectGuard(), delegateQueue: nil)
    }

    /// Shared by clients built without a session of their own (connection test,
    /// App Intents). Services refreshed by the app use `HTTPSessionPool`.
    public static let defaultSessions = RenewableSession(make: HTTPClient.makeSession)

    /// Largest body accepted (the biggest legitimate one, 5000 Docker log lines,
    /// stays well below). A larger answer, from a misbehaving server, a compromised
    /// proxy or a too-broad PromQL query, is dropped instead of being decoded.
    public static let defaultMaxResponseBytes = 20 * 1024 * 1024

    /// `session`: a fixed session (tests); a renewal creates another one with the
    /// same configuration and delegate.
    public convenience init(
        session: URLSession? = nil, timeout: TimeInterval = 10, maxAttempts: Int = 2, backoff: TimeInterval = 1.5,
        maxResponseBytes: Int = HTTPClient.defaultMaxResponseBytes
    ) {
        let sessions = session.map { session in
            RenewableSession(make: Self.sessionFactory(startingWith: session))
        } ?? Self.defaultSessions
        self.init(
            sessions: sessions, timeout: timeout, maxAttempts: maxAttempts, backoff: backoff,
            maxResponseBytes: maxResponseBytes, label: nil, log: nil
        )
    }

    public init(
        sessions: RenewableSession, timeout: TimeInterval = 10, maxAttempts: Int = 2, backoff: TimeInterval = 1.5,
        maxResponseBytes: Int = HTTPClient.defaultMaxResponseBytes, label: RequestLog.Label?, log: RequestLog?
    ) {
        self.sessions = sessions
        self.timeout = timeout
        self.maxAttempts = max(1, maxAttempts)
        self.backoff = backoff
        self.maxResponseBytes = max(1, maxResponseBytes)
        self.label = label
        self.log = log
    }

    /// Returns `first` once, then new sessions with its configuration and delegate.
    private static func sessionFactory(startingWith first: URLSession) -> @Sendable () -> URLSession {
        let pending = Mutex<URLSession?>(first)
        return {
            if let session = pending.withLock({ state -> URLSession? in
                defer { state = nil }
                return state
            }) {
                return session
            }
            return URLSession(configuration: first.configuration, delegate: first.delegate, delegateQueue: nil)
        }
    }

    public func send(_ spec: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
        guard spec.url.scheme?.lowercased() == "https" else {
            throw HTTPClientError.nonHTTPSURL
        }

        var request = URLRequest(url: spec.url)
        request.httpMethod = spec.method.rawValue
        request.timeoutInterval = timeout
        request.httpBody = spec.body
        for (key, value) in spec.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var attempt = 0
        var transportFailures = 0
        var retriedMisdirected = false
        var retriedReset = false
        var fresh = false
        while true {
            attempt += 1
            #if canImport(os)
            Self.logger.debug("\(spec.redactedDescription, privacy: .private) attempt \(attempt, privacy: .public)")
            #endif
            let started = Date.now
            let (result, connection, used) = await Self.load(request, on: sessions, maxBytes: maxResponseBytes)
            guard let session = used else {
                // Service removed meanwhile: its result would be discarded.
                throw CancellationError()
            }
            switch result {
            case .success(let (data, response)):
                guard let http = response as? HTTPURLResponse else {
                    record(spec, attempt, started, nil, connection, .invalidResponse, fresh)
                    throw HTTPClientError.invalidResponse
                }
                if http.statusCode == 421 {
                    // Misdirected Request: this connection serves another host
                    // (HTTP/2 coalescing through one reverse proxy). Never the
                    // token's fault. A new session means a new connection; a POST
                    // is never sent twice.
                    record(spec, attempt, started, http, connection, .misdirected, fresh)
                    sessions.renew(replacing: session)
                    if spec.method.allowsRetry && !retriedMisdirected {
                        retriedMisdirected = true
                        fresh = true
                        continue
                    }
                    return (data, http)
                }
                if let (error, outcome) = Self.refusal(http, body: data) {
                    record(spec, attempt, started, http, connection, outcome, fresh)
                    throw error
                }
                // After 401/403, which pause the service whatever their size. Also
                // covers platforms where the download can't be stopped early.
                if data.count > maxResponseBytes {
                    record(spec, attempt, started, http, connection, .invalidResponse, fresh)
                    throw HTTPClientError.invalidResponse
                }
                record(spec, attempt, started, http, connection, (200..<400).contains(http.statusCode) ? .ok : .httpStatus, fresh)
                return (data, http)
            case .failure(let error):
                // A cancelled request is not an unreachable service.
                if Task.isCancelled {
                    record(spec, attempt, started, nil, connection, .cancelled, fresh)
                    throw CancellationError()
                }
                // Body over the limit, stopped while downloading: never retried. A
                // refused token is still a refused token (service paused).
                if let stopped = error as? StoppedOversized {
                    if let http = stopped.response, let (error, outcome) = Self.refusal(http, body: Data()) {
                        record(spec, attempt, started, http, connection, outcome, fresh)
                        throw error
                    }
                    record(spec, attempt, started, stopped.response, connection, .invalidResponse, fresh)
                    throw HTTPClientError.invalidResponse
                }
                if let error = error as? HTTPClientError {
                    record(spec, attempt, started, nil, connection, .invalidResponse, fresh)
                    throw error
                }
                if (error as? URLError)?.code == .cancelled {
                    record(spec, attempt, started, nil, connection, .cancelled, fresh)
                    // Not this task: its session was reset (network path changed)
                    // or the service removed. A GET goes again once on the new
                    // session; a POST may have been sent and is never resent.
                    if sessions.isClosed { throw CancellationError() }
                    if spec.method.allowsRetry && !retriedReset && sessions.current !== session {
                        retriedReset = true
                        fresh = true
                        continue
                    }
                    throw HTTPClientError.unreachable
                }
                record(spec, attempt, started, nil, connection, Self.outcome(of: error), fresh)
                transportFailures += 1
                let canRetry = spec.method.allowsRetry && transportFailures < maxAttempts && Self.isRetryable(error)
                guard canRetry else { throw HTTPClientError.unreachable }
                // The connection may be dead (VPN route changed) while the session
                // would reuse it: retry on a new one.
                if Self.suggestsDeadConnection(error) {
                    sessions.renew(replacing: session)
                    fresh = true
                }
                // Spaced backoff: the delay grows with each attempt.
                try await Task.sleep(for: .seconds(backoff * Double(transportFailures)))
            }
        }
    }

    // MARK: Transport and metrics

    /// Connection facts from URLSessionTaskMetrics, copied out of the delegate.
    struct ConnectionInfo: Sendable {
        var networkProtocol: String?
        var reused: Bool?
        var localPort: Int?
    }

    /// Runs `request` on the current session of `sessions`; the session is nil
    /// when the service was removed (no task started).
    private static func load(
        _ request: URLRequest, on sessions: RenewableSession, maxBytes: Int
    ) async -> (Result<(Data, URLResponse), any Error>, ConnectionInfo?, URLSession?) {
        #if canImport(FoundationNetworking)
        let collector: MetricsCollector? = nil
        let delegate: (any URLSessionTaskDelegate & Sendable)? = nil
        #else
        // Task delegate: only collects metrics; redirects stay with the session's
        // SameOriginRedirectGuard.
        let collector: MetricsCollector? = MetricsCollector()
        let delegate: (any URLSessionTaskDelegate & Sendable)? = collector
        #endif
        let started = Mutex<(task: URLSessionDataTask, session: URLSession)?>(nil)
        let budget = ByteBudget(limit: maxBytes)
        let result: Result<(Data, URLResponse), any Error> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let launched = sessions.startTask(request, delegate: delegate, onLaunch: { task, session in
                    started.withLock { $0 = (task, session) }
                    budget.watch(task)
                }) { data, response, error in
                    if budget.exceeded {
                        // The headers arrived before the download was stopped.
                        let received = response ?? started.withLock { $0 }?.task.response
                        continuation.resume(returning: .failure(StoppedOversized(response: received as? HTTPURLResponse)))
                    } else if let error {
                        continuation.resume(returning: .failure(error))
                    } else if let data, let response {
                        continuation.resume(returning: .success((data, response)))
                    } else {
                        continuation.resume(returning: .failure(URLError(.badServerResponse)))
                    }
                }
                guard let launched else {
                    continuation.resume(returning: .failure(CancellationError()))
                    return
                }
                if Task.isCancelled { launched.task.cancel() }
            }
        } onCancel: {
            started.withLock { $0 }?.task.cancel()
        }
        return (result, collector?.info, started.withLock { $0 }?.session)
    }

    /// A download stopped by `ByteBudget`, with the status line already received.
    private struct StoppedOversized: Error {
        let response: HTTPURLResponse?
    }

    /// 401 and 403 pause the service whatever the size of their body; nil for any
    /// other status. Without the body (download stopped), a 403 is told apart by
    /// its Content-Type only.
    private static func refusal(
        _ http: HTTPURLResponse, body: Data
    ) -> (HTTPClientError, RequestLog.Outcome)? {
        switch http.statusCode {
        case 401:
            return (.unauthorized, .unauthorized)
        case 403:
            return isProxyBlockPage(http, body: body)
                ? (.blockedByProxy, .blockedByProxy)
                : (.forbidden, .forbiddenByService)
        default:
            return nil
        }
    }

    /// Stops a download as soon as the announced or received size passes the limit,
    /// instead of holding the whole body in memory first. The observations end
    /// with the budget, once the request has finished.
    private final class ByteBudget: Sendable {
        private let limit: Int
        private let exceededFlag = Mutex(false)
        #if !canImport(FoundationNetworking)
        private let observations = Mutex<[NSKeyValueObservation]>([])
        #endif

        init(limit: Int) { self.limit = limit }

        var exceeded: Bool { exceededFlag.withLock { $0 } }

        func watch(_ task: URLSessionDataTask) {
            #if !canImport(FoundationNetworking)
            let limit = Int64(limit)
            let check: @Sendable (URLSessionTask) -> Void = { [weak self] task in
                guard let self, task.countOfBytesExpectedToReceive > limit || task.countOfBytesReceived > limit else { return }
                let first = exceededFlag.withLock { exceeded -> Bool in
                    defer { exceeded = true }
                    return !exceeded
                }
                if first { task.cancel() }
            }
            let received = task.observe(\.countOfBytesReceived) { task, _ in check(task) }
            let expected = task.observe(\.countOfBytesExpectedToReceive) { task, _ in check(task) }
            observations.withLock { $0 = [received, expected] }
            #endif
        }
    }

    #if canImport(FoundationNetworking)
    private final class MetricsCollector: Sendable {
        var info: ConnectionInfo? { nil }
    }
    #else
    private final class MetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
        private let state = Mutex<ConnectionInfo?>(nil)

        var info: ConnectionInfo? { state.withLock { $0 } }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            // The last transaction is the one that produced the response.
            guard let transaction = metrics.transactionMetrics.last else { return }
            let info = ConnectionInfo(
                networkProtocol: transaction.networkProtocolName,
                reused: transaction.isReusedConnection,
                localPort: transaction.localPort
            )
            state.withLock { $0 = info }
        }
    }
    #endif

    private func record(
        _ spec: HTTPRequestSpec, _ attempt: Int, _ started: Date, _ response: HTTPURLResponse?,
        _ connection: ConnectionInfo?, _ outcome: RequestLog.Outcome, _ fresh: Bool
    ) {
        guard let log else { return }
        log.append(.request(RequestLog.Request(
            method: spec.method.rawValue,
            path: RequestLog.loggedPath(spec.url, basePath: label?.basePath ?? ""),
            attempt: attempt,
            statusCode: response?.statusCode,
            contentType: RequestLog.loggedHeader(response?.value(forHTTPHeaderField: "Content-Type")),
            server: RequestLog.loggedHeader(response?.value(forHTTPHeaderField: "Server")),
            networkProtocol: connection?.networkProtocol,
            reusedConnection: connection?.reused,
            localPort: connection?.localPort,
            duration: Date.now.timeIntervalSince(started),
            outcome: outcome,
            freshConnection: fresh,
            context: RequestLog.context
        )), label: label)
    }

    static func outcome(of error: any Error) -> RequestLog.Outcome {
        guard let code = (error as? URLError)?.code else { return .otherTransportError }
        switch code {
        case .timedOut: return .timedOut
        case .networkConnectionLost: return .connectionLost
        case .cannotConnectToHost: return .cannotConnect
        case .dnsLookupFailed, .cannotFindHost: return .dnsFailure
        case .notConnectedToInternet: return .notConnected
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return .tlsFailure
        case .cancelled: return .cancelled
        default: return .otherTransportError
        }
    }

    /// Errors after which the session's connection should not be reused.
    private static func suggestsDeadConnection(_ error: any Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return code == .timedOut || code == .networkConnectionLost
    }

    /// A 403 is the reverse proxy's, not the service's, when it is an HTML page:
    /// the services PatchNode talks to answer their API with JSON or plain text.
    /// Exception: docker-socket-proxy (HAProxy) refuses a disabled endpoint with its
    /// own HTML page, "Request forbidden by administrative rules": that is the
    /// service's refusal. (A 401 HTML page is a proxy asking for Basic credentials:
    /// a real refusal too.)
    public static func isProxyBlockPage(_ response: HTTPURLResponse, body: Data) -> Bool {
        let text = String(decoding: body.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if text.contains("request forbidden by administrative rules") { return false }
        if let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased(), type.contains("text/html") {
            return true
        }
        return text.hasPrefix("<!doctype html") || text.hasPrefix("<html")
    }

    private static func isRetryable(_ error: any Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

/// Follows a redirect only if it stays on the same scheme, host and port, so an
/// Authorization / X-API-Key header can never be replayed to another server.
/// Observes server-trust challenges to note certificate expiry, but never decides
/// on them: the answer is always `.performDefaultHandling`. Any change here needs a
/// security review.
public final class SameOriginRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.isSameOrigin(task.originalRequest?.url, request.url) ? request : nil)
    }

    #if canImport(Security)
    /// Server trust: reads the expiry of the certificate the server presents, once
    /// per new connection, and records it only if the system's own evaluation
    /// accepts the chain. The decision is always the system's
    /// (`.performDefaultHandling`): nothing here can accept a certificate.
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            Self.recordExpiry(of: trust, host: challenge.protectionSpace.host, port: challenge.protectionSpace.port)
        }
        // Answered at once: the expiry is read on another queue, so neither the
        // handshake nor this session's delegate queue waits for it.
        completionHandler(.performDefaultHandling, nil)
    }

    private static let trustQueue = DispatchQueue(label: "fr.antxis.apple.labwatch.certificate-expiry", qos: .utility)

    private static func recordExpiry(of trust: SecTrust, host: String, port: Int) {
        let port = port == 0 ? 443 : port
        // The chain as plain bytes: the challenge's trust object stays with the
        // system, a new one is evaluated off the handshake's path.
        let chain = ((SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []).map { SecCertificateCopyData($0) as Data }
        guard let leaf = chain.first else { return }
        trustQueue.async {
            // Read only from a chain the system accepts for this host (the
            // evaluation may fetch missing intermediates).
            let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            var copy: SecTrust?
            guard certificates.count == chain.count,
                  SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateSSL(true, host as CFString), &copy) == errSecSuccess,
                  let copy, SecTrustEvaluateWithError(copy, nil),
                  let notAfter = X509Validity.notAfter(der: leaf)
            else { return }
            CertificateRegistry.shared.record(host: host, port: port, notAfter: notAfter)
        }
    }
    #endif

    static func isSameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              let lhsScheme = lhs.scheme?.lowercased(), lhsScheme == "https",
              rhs.scheme?.lowercased() == lhsScheme,
              let lhsHost = lhs.host?.lowercased(), lhsHost == rhs.host?.lowercased()
        else { return false }
        return (lhs.port ?? 443) == (rhs.port ?? 443)
    }
}
