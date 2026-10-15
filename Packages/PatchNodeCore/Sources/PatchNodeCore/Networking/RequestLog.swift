import Foundation
import Synchronization

/// In-memory journal of the last requests and pause events, for Settings >
/// Diagnostics. It never holds a secret: no header value other than Content-Type
/// and Server, no body, no query value, no host or address. Lost when the app quits.
public final class RequestLog: Sendable {
    public static let shared = RequestLog()
    public static let defaultCapacity = 200

    /// Whether the request is an ordinary one or the first after a pause: set by
    /// the store around a refresh, read by `HTTPClient` when it logs.
    @TaskLocal public static var context: Context = .normal

    public enum Context: Sendable, Hashable {
        case normal
        /// First request after an automatic pause ended (`attempt` = how many
        /// times the proxy had refused in a row).
        case resumeProbe(attempt: Int)
    }

    /// Which service a client talks for.
    public struct Label: Sendable, Hashable {
        public let serviceID: UUID
        public let serviceName: String
        /// Path of the service's configured URL (a reverse-proxy prefix can be
        /// private): left out of the logged paths.
        public let basePath: String

        public init(serviceID: UUID, serviceName: String, baseURL: URL? = nil) {
            self.serviceID = serviceID
            self.serviceName = serviceName
            self.basePath = baseURL.map(Self.normalizedBasePath) ?? ""
        }

        /// "" for a URL at the root, otherwise its path without the final "/".
        static func normalizedBasePath(_ url: URL) -> String {
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
            var trimmed = path
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            return trimmed
        }
    }

    /// How a request ended, from the app's point of view.
    public enum Outcome: String, Sendable, Hashable {
        case ok
        /// Any status other than 2xx/3xx, 401, 403 and 421 (returned to the caller).
        case httpStatus
        case unauthorized
        /// 403 from the service (JSON / text): missing rights.
        case forbiddenByService
        /// 403 HTML page from the reverse proxy.
        case blockedByProxy
        /// 421 Misdirected Request: the connection belongs to another host.
        case misdirected
        case timedOut
        case connectionLost
        case cannotConnect
        case dnsFailure
        case notConnected
        case tlsFailure
        case cancelled
        case invalidResponse
        case otherTransportError
    }

    public struct Request: Sendable, Hashable {
        public let method: String
        /// Path, then query parameter names only (values dropped).
        public let path: String
        /// 1-based, per call to `send` (a 421 retry counts as an attempt).
        public let attempt: Int
        public let statusCode: Int?
        public let contentType: String?
        public let server: String?
        /// ALPN protocol from URLSessionTaskMetrics ("h2", "http/1.1", "h3").
        public let networkProtocol: String?
        public let reusedConnection: Bool?
        /// Local TCP port: two requests with the same port shared one connection.
        public let localPort: Int?
        public let duration: TimeInterval
        public let outcome: Outcome
        /// Sent on a session created just before (after a 421 or a dead connection).
        public let freshConnection: Bool
        public let context: Context

        public init(
            method: String, path: String, attempt: Int, statusCode: Int?, contentType: String?, server: String?,
            networkProtocol: String?, reusedConnection: Bool?, localPort: Int?, duration: TimeInterval,
            outcome: Outcome, freshConnection: Bool, context: Context
        ) {
            self.method = method
            self.path = path
            self.attempt = attempt
            self.statusCode = statusCode
            self.contentType = contentType
            self.server = server
            self.networkProtocol = networkProtocol
            self.reusedConnection = reusedConnection
            self.localPort = localPort
            self.duration = duration
            self.outcome = outcome
            self.freshConnection = freshConnection
            self.context = context
        }
    }

    public enum Event: Sendable, Hashable {
        /// `resumeAfter` nil: until a pull to refresh.
        case paused(reason: PauseReason, resumeAfter: TimeInterval?)
        case resumed(ResumeCause)
        /// Every session was dropped (network path changed).
        case sessionsReset
        /// A terminal or console opened (kind only, never its content).
        case terminalOpened(TerminalKind)
        /// It ended after `duration` seconds.
        case terminalEnded(TerminalKind, duration: TimeInterval, reason: TerminalEndReason)
        /// Proxmox guests (VMIDs) a refresh no longer lists while their node
        /// answers: deleted, or rights lost on them — never assumed deleted.
        case guestsNoLongerListed(vmids: [Int])
    }

    public enum ResumeCause: String, Sendable, Hashable {
        case succeeded
        case pullToRefresh
        case networkChanged
    }

    public enum Kind: Sendable, Hashable {
        case request(Request)
        case event(Event)
    }

    public struct Entry: Sendable, Hashable, Identifiable {
        public let id: Int
        public let date: Date
        public let serviceID: UUID?
        public let serviceName: String
        public let kind: Kind
    }

    private struct State {
        var nextID = 0
        var entries: [Entry] = []
        var version = 0
    }

    public let capacity: Int
    private let state = Mutex(State())

    public init(capacity: Int = RequestLog.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func append(_ kind: Kind, label: Label?, date: Date = .now) {
        state.withLock { state in
            state.entries.append(Entry(
                id: state.nextID, date: date, serviceID: label?.serviceID,
                serviceName: label?.serviceName ?? "—", kind: kind
            ))
            state.nextID &+= 1
            state.version &+= 1
            if state.entries.count > capacity {
                state.entries.removeFirst(state.entries.count - capacity)
            }
        }
    }

    /// Oldest first.
    public func entries() -> [Entry] {
        state.withLock { $0.entries }
    }

    public func clear() {
        state.withLock { state in
            state.entries.removeAll()
            state.version &+= 1
        }
    }

    /// Changes on every append or clear: a screen reads `entries()` only when it
    /// moved.
    public var version: Int {
        state.withLock { $0.version }
    }

    /// API path relative to the service's URL, then query parameter names, never
    /// their values (a query may carry a credential):
    /// `/api2/json/nodes/node-a/qemu/100/rrddata?timeframe&cf`. A path outside
    /// `basePath` keeps only its last component.
    public static func loggedPath(_ url: URL, basePath: String = "") -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "?" }
        var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if !basePath.isEmpty {
            if path == basePath {
                path = "/"
            } else if path.hasPrefix(basePath + "/") {
                path = String(path.dropFirst(basePath.count))
            } else {
                path = "…/" + (path.split(separator: "/").last.map(String.init) ?? "")
            }
        }
        let names = (components.queryItems ?? []).map(\.name)
        return names.isEmpty ? path : path + "?" + names.joined(separator: "&")
    }

    /// Header values kept in the log: short and without control characters.
    static func loggedHeader(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(cleaned.prefix(80))
    }
}

// MARK: - Text export

extension RequestLog.Entry {
    /// VMIDs written out in a "no longer listed" line.
    static let listedVMIDs = 10

    /// One line, for "Copy" / "Share": technical English, like the rest of a log.
    public var logLine: String {
        let time = date.formatted(.iso8601.time(includingFractionalSeconds: true))
        switch kind {
        case .request(let r):
            var parts = ["\(time) [\(serviceName)] \(r.method) \(r.path)"]
            parts.append("#\(r.attempt)")
            parts.append(r.statusCode.map { "HTTP \($0)" } ?? "no response")
            parts.append(r.outcome.rawValue)
            if let type = r.contentType { parts.append("type=\(type)") }
            if let server = r.server { parts.append("server=\(server)") }
            if let proto = r.networkProtocol { parts.append("proto=\(proto)") }
            if let reused = r.reusedConnection { parts.append(reused ? "reused" : "new-conn") }
            if let port = r.localPort { parts.append("lport=\(port)") }
            if r.freshConnection { parts.append("fresh-session") }
            if case .resumeProbe(let attempt) = r.context { parts.append("resume-probe#\(attempt)") }
            parts.append("\(Int((r.duration * 1000).rounded())) ms")
            return parts.joined(separator: " ")
        case .event(let event):
            switch event {
            case .paused(let reason, let after):
                let until = after.map { "resume in \(Int($0)) s" } ?? "until pull to refresh"
                return "\(time) [\(serviceName)] PAUSED (\(reason.rawValue)), \(until)"
            case .resumed(let cause):
                return "\(time) [\(serviceName)] RESUMED (\(cause.rawValue))"
            case .sessionsReset:
                return "\(time) [\(serviceName)] SESSIONS RESET (network path changed)"
            case .terminalOpened(let kind):
                return "\(time) [\(serviceName)] TERMINAL OPENED (\(kind.rawValue))"
            case .terminalEnded(let kind, let duration, let reason):
                return "\(time) [\(serviceName)] TERMINAL ENDED (\(kind.rawValue)) \(reason.logValue) after \(Int(duration.rounded())) s"
            case .guestsNoLongerListed(let vmids):
                let shown = vmids.prefix(Self.listedVMIDs).map(String.init).joined(separator: ", ")
                let more = vmids.count > Self.listedVMIDs ? " +\(vmids.count - Self.listedVMIDs)" : ""
                return "\(time) [\(serviceName)] GUESTS NO LONGER LISTED (\(shown)\(more)) while their node answers: "
                    + "deleted or moved, or insufficient rights on them? An ACL on /vms/<id> without PVEAuditor hides the guest. "
                    + "Check: pveum user token permissions <user> <tokenid> --path /vms/<id>"
            }
        }
    }
}

extension RequestLog {
    /// Whole journal as text, oldest first.
    public func exportText() -> String {
        entries().map(\.logLine).joined(separator: "\n")
    }
}
