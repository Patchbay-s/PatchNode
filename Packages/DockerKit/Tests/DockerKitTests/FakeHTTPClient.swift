import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PatchNodeCore

/// Simulated transport: records every received spec and replays a configured outcome,
/// optionally per URL path. No network access; 401/403 and timeouts are simulated by
/// throwing what the real `HTTPClient` throws (`HTTPClientError.unauthorized`,
/// `.forbidden`, `.unreachable` once its own timeout fires).
actor FakeHTTPClient: HTTPClientProtocol {
    enum Outcome: Sendable {
        case response(status: Int, body: Data)
        case failure(any Error & Sendable)

        static func json(_ string: String, status: Int = 200) -> Outcome {
            .response(status: status, body: Data(string.utf8))
        }

        static let unauthorized = Outcome.failure(HTTPClientError.unauthorized)
        static let forbidden = Outcome.failure(HTTPClientError.forbidden)
        static let timeout = Outcome.failure(HTTPClientError.unreachable)
        static let serverError = Outcome.json(#"{"message":"internal error"}"#, status: 500)
    }

    /// Exact URL path → outcome; `fallback` for everything else.
    private let routes: [String: Outcome]
    private let fallback: Outcome
    private(set) var receivedSpecs: [HTTPRequestSpec] = []

    init(_ outcome: Outcome) {
        self.routes = [:]
        self.fallback = outcome
    }

    init(routes: [String: Outcome], fallback: Outcome = .json(#"{"message":"page not found"}"#, status: 404)) {
        self.routes = routes
        self.fallback = fallback
    }

    static func json(_ string: String, status: Int = 200) -> FakeHTTPClient {
        FakeHTTPClient(.json(string, status: status))
    }

    var receivedURLs: [String] { receivedSpecs.map(\.url.absoluteString) }
    var receivedPaths: [String] { receivedSpecs.map(\.url.path) }

    func send(_ request: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
        receivedSpecs.append(request)
        switch routes[request.url.path] ?? fallback {
        case let .response(status, body):
            let response = HTTPURLResponse(
                url: request.url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}
