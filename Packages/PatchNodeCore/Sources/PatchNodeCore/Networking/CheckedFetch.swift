import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPClientProtocol {
    /// Sends `spec` and returns the body of a 200 response, mapping every failure
    /// to `ServiceProviderError` the same way for all providers. Cancellation is
    /// rethrown as-is.
    public func fetchOK(_ spec: HTTPRequestSpec) async throws -> Data {
        let (data, response) = try await fetchResponse(spec)
        guard response.statusCode == 200 else {
            throw ServiceProviderError.unexpectedStatus(response.statusCode)
        }
        return data
    }

    /// Same error mapping as `fetchOK`, but any status other than 401/403 is
    /// returned with its body (e.g. Prometheus explains a bad query in a 400).
    public func fetchResponse(_ spec: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await send(spec)
        } catch let error as CancellationError {
            throw error
        } catch HTTPClientError.unauthorized {
            throw ServiceProviderError.unauthorized
        } catch HTTPClientError.forbidden {
            throw ServiceProviderError.forbidden
        } catch HTTPClientError.blockedByProxy {
            throw ServiceProviderError.blockedByProxy
        } catch HTTPClientError.invalidResponse {
            throw ServiceProviderError.invalidResponse
        } catch {
            throw ServiceProviderError.unreachable
        }
    }

    /// `fetchOK` followed by JSON decoding (`.decodingFailed` on error).
    public func fetchJSON<T: Decodable>(_ spec: HTTPRequestSpec, as type: T.Type = T.self) async throws -> T {
        let data = try await fetchOK(spec)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ServiceProviderError.decodingFailed
        }
    }
}
