import Foundation

public struct HTTPRequestSpec: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        /// Portainer stack updates (1.2). Like POST, never retried.
        case put = "PUT"

        /// Only reads are ever sent twice (CLAUDE.md: no retry on POST, nor
        /// on any request that changes a state).
        public var allowsRetry: Bool { self == .get }
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    /// Compared case-insensitively: covers Authorization, X-API-Key and X-Api-Key,
    /// plus headers no client sends today but that would carry a secret.
    static let sensitiveHeaderNames: Set<String> = [
        "authorization", "x-api-key", "proxy-authorization", "cookie", "x-auth-token",
    ]

    /// URL without user info or query, which may carry credentials.
    private static func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<unparseable URL>"
        }
        components.user = nil
        components.password = nil
        if components.query != nil { components.query = "<redacted>" }
        components.fragment = nil
        return components.string ?? "<unparseable URL>"
    }

    /// Log-safe description: sensitive header values are replaced and the body is
    /// never included.
    public var redactedDescription: String {
        let maskedHeaders = headers
            .map { key, value -> String in
                Self.sensitiveHeaderNames.contains(key.lowercased()) ? "\(key): <redacted>" : "\(key): \(value)"
            }
            .sorted()
            .joined(separator: ", ")
        return "\(method.rawValue) \(Self.redactedURLString(url)) [\(maskedHeaders)]"
    }
}
