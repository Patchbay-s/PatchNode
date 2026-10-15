import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PatchNodeCore

/// Replays one outcome for every request, without any network access.
private struct ScriptedHTTPClient: HTTPClientProtocol {
    enum Outcome: Sendable {
        case response(status: Int, body: String)
        case failure(any Error & Sendable)
    }

    let outcome: Outcome

    func send(_ request: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
        switch outcome {
        case let .response(status, body):
            let response = HTTPURLResponse(url: request.url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        case let .failure(error):
            throw error
        }
    }
}

@Suite("CheckedFetch")
struct FetchResponseTests {
    private let spec = HTTPRequestSpec(
        method: .get, url: URL(string: "https://service.example.invalid/api/v1/query")!,
        headers: ["Authorization": "Bearer fake-token-1234"]
    )

    @Test(arguments: [200, 400, 404, 422, 500, 503])
    func fetchResponseReturnsBodyAndStatus(status: Int) async throws {
        let body = #"{"status":"error","error":"parse error"}"#
        let (data, response) = try await ScriptedHTTPClient(outcome: .response(status: status, body: body)).fetchResponse(spec)
        #expect(response.statusCode == status)
        #expect(String(decoding: data, as: UTF8.self) == body)
    }

    @Test(arguments: [
        (HTTPClientError.unauthorized, ServiceProviderError.unauthorized),
        (.forbidden, .forbidden),
        (.unreachable, .unreachable),
        (.invalidResponse, .invalidResponse),
        (.nonHTTPSURL, .unreachable),
    ])
    func fetchResponseMapsClientErrorsLikeFetchOK(error: HTTPClientError, expected: ServiceProviderError) async throws {
        let client = ScriptedHTTPClient(outcome: .failure(error))
        await #expect(throws: expected) { _ = try await client.fetchResponse(spec) }
        await #expect(throws: expected) { _ = try await client.fetchOK(spec) }
    }

    @Test func fetchResponseMapsURLErrorToUnreachable() async throws {
        let client = ScriptedHTTPClient(outcome: .failure(URLError(.timedOut)))
        await #expect(throws: ServiceProviderError.unreachable) { _ = try await client.fetchResponse(spec) }
    }

    @Test func fetchResponseRethrowsCancellation() async throws {
        let client = ScriptedHTTPClient(outcome: .failure(CancellationError()))
        await #expect(throws: CancellationError.self) { _ = try await client.fetchResponse(spec) }
        await #expect(throws: CancellationError.self) { _ = try await client.fetchOK(spec) }
    }

    @Test func fetchOKReturnsBodyOn200() async throws {
        let data = try await ScriptedHTTPClient(outcome: .response(status: 200, body: "ok")).fetchOK(spec)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
    }

    @Test(arguments: [201, 204, 400, 404, 500])
    func fetchOKThrowsUnexpectedStatusOtherwise(status: Int) async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(status)) {
            _ = try await ScriptedHTTPClient(outcome: .response(status: status, body: "{}")).fetchOK(spec)
        }
    }

    @Test func fetchJSONMapsInvalidBodyToDecodingFailed() async throws {
        struct Payload: Decodable { let status: String }
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await ScriptedHTTPClient(outcome: .response(status: 200, body: "<html>")).fetchJSON(spec, as: Payload.self)
        }
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await ScriptedHTTPClient(outcome: .response(status: 200, body: "")).fetchJSON(spec, as: Payload.self)
        }
    }
}
