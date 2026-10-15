import Foundation
import Synchronization
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Demo mode transport: requests to the reserved `patchnode-demo.invalid` domain
/// never leave the device. `HTTPClient.makeSession` installs `DemoURLProtocol`,
/// which answers them from the responders registered here; every other host is
/// left to the normal network stack. `.invalid` never resolves (RFC 2606), so a
/// demo request could not reach a server even if it slipped past the protocol.
public enum DemoServer {
    public static let domain = "patchnode-demo.invalid"

    public static func isDemo(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    private static let responders = Mutex<[String: any DemoResponder]>([:])

    /// Registers the responder answering for `host` (lowercased).
    public static func register(_ responder: any DemoResponder, host: String) {
        responders.withLock { $0[host.lowercased()] = responder }
    }

    static func responder(for host: String) -> (any DemoResponder)? {
        responders.withLock { $0[host.lowercased()] }
    }
}

/// What a demo request looks like to a responder: method, API path (decoded),
/// query values and body. Headers are not passed on (no credential needed).
public struct DemoRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let body: Data?

    public init(method: String, path: String, query: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }

    /// Path segments without empty ones: `/api2/json/nodes` → ["api2", "json", "nodes"].
    public var segments: [String] {
        path.split(separator: "/").map(String.init)
    }
}

public struct DemoResponse: Sendable {
    public let status: Int
    public let contentType: String
    public let body: Data

    public init(status: Int = 200, contentType: String = "application/json", body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func json(_ text: String, status: Int = 200) -> DemoResponse {
        DemoResponse(status: status, body: Data(text.utf8))
    }

    /// Serializes a tree of dictionaries, arrays, strings and numbers.
    public static func json(object: Any, status: Int = 200) -> DemoResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return DemoResponse(status: status, body: data)
    }

    public static let notFound = DemoResponse.json(#"{"message":"Not available in demo mode"}"#, status: 404)
}

public protocol DemoResponder: Sendable {
    func respond(to request: DemoRequest, now: Date) -> DemoResponse
}

/// Answers demo hosts from the registered responders, synchronously and without
/// any network access.
public final class DemoURLProtocol: URLProtocol {
    override public class func canInit(with request: URLRequest) -> Bool {
        request.url.map(DemoServer.isDemo) ?? false
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let demoRequest = DemoRequest(
            method: request.httpMethod ?? "GET",
            path: components?.path ?? url.path,
            query: query,
            body: request.httpBody ?? Self.readBody(request.httpBodyStream)
        )
        let answer = DemoServer.responder(for: host)?.respond(to: demoRequest, now: .now) ?? .notFound
        guard let response = HTTPURLResponse(
            url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": answer.contentType, "Server": "patchnode-demo"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}

    private static func readBody(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
