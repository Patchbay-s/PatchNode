import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PatchNodeCore

/// Simulated transport: records every received spec and replays a configured outcome.
/// No network access; timeouts are simulated by throwing `HTTPClientError.unreachable`
/// (what the real `HTTPClient` throws once its own timeout fires).
actor FakeHTTPClient: HTTPClientProtocol {
    enum Outcome: Sendable {
        case response(status: Int, body: Data)
        case failure(any Error & Sendable)
    }

    /// Replayed in order; the last one repeats once the others are consumed (polling).
    private var outcomes: [Outcome]
    private(set) var receivedSpecs: [HTTPRequestSpec] = []

    init(_ outcome: Outcome) {
        self.outcomes = [outcome]
    }

    /// One outcome per request, in order; the last one is repeated.
    init(sequence: [Outcome]) {
        precondition(!sequence.isEmpty, "FakeHTTPClient needs at least one outcome")
        self.outcomes = sequence
    }

    static func json(_ string: String, status: Int = 200) -> FakeHTTPClient {
        FakeHTTPClient(.response(status: status, body: Data(string.utf8)))
    }

    func send(_ request: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
        receivedSpecs.append(request)
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        switch outcome {
        case let .response(status, body):
            let response = HTTPURLResponse(
                url: request.url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json;charset=UTF-8"]
            )!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}
