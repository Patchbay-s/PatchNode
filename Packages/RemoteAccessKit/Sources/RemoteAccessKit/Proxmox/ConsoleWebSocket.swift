import Foundation
import PatchNodeCore

/// One websocket to a Proxmox console, opened natively so the API token goes
/// in the upgrade's `Authorization` header (never into a web page). Same
/// rules as the HTTP client: HTTPS only, the system decides on certificates,
/// redirects only to the same origin, no cookies or cache.
public final class ConsoleWebSocket: Sendable {
    private let task: URLSessionWebSocketTask
    private let session: URLSession

    /// Not `timeoutIntervalForResource`-bound: a console stays open for hours.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 75
        configuration.timeoutIntervalForResource = 7 * 24 * 3600
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: SameOriginRedirectGuard(), delegateQueue: nil)
    }

    public init(url: URL, headers: [String: String]) throws {
        guard url.scheme == "wss" else { throw ConsoleFailure.unreachable }
        var request = URLRequest(url: url, timeoutInterval: 10)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        session = Self.makeSession()
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
    }

    /// Opens the connection with a first message (handshake), returns once the
    /// server answered something.
    public func open(sending first: Data?) async throws -> Data {
        task.resume()
        do {
            return try await withTaskCancellationHandler {
                if let first { try await task.send(.data(first)) }
                return try await receive()
            } onCancel: {
                close()
            }
        } catch {
            let reason = failure(error)
            // A failed console never keeps its session (and delegate).
            close()
            throw reason
        }
    }

    public func receive() async throws -> Data {
        do {
            switch try await task.receive() {
            case .data(let data): return data
            case .string(let string): return Data(string.utf8)
            @unknown default: return Data()
            }
        } catch {
            throw failure(error)
        }
    }

    public func send(_ data: Data) async throws {
        do {
            try await task.send(.data(data))
        } catch {
            throw failure(error)
        }
    }

    public func sendPing() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            task.sendPing { _ in continuation.resume() }
        }
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    /// The upgrade's HTTP status says why it failed (401: token refused for
    /// consoles, older PVE; 403: privilege).
    private func failure(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        if let status, status != 101 { return ConsoleFailure.fromUpgradeStatus(status) }
        if (error as? URLError)?.code == .cancelled { return CancellationError() }
        return ConsoleFailure.unreachable
    }
}
