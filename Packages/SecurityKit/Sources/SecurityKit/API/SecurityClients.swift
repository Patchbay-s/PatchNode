import Foundation
import PatchNodeCore

/// Joins path segments onto a base URL, each one percent-encoded.
func endpoint(_ baseURL: URL, _ segments: [String], query: [URLQueryItem] = []) -> URL {
    var url = baseURL
    for segment in segments {
        url = url.appending(component: segment)
    }
    if !query.isEmpty {
        url = url.appending(queryItems: query)
    }
    return url
}

func basicHeader(_ credential: String) -> [String: String] {
    guard !credential.isEmpty else { return [:] }
    return ["Authorization": "Basic \(Data(credential.utf8).base64EncodedString())"]
}

// MARK: - CrowdSec

/// CrowdSec Local API with a bouncer key (`cscli bouncers add PatchNode`).
public struct CrowdSecClient: Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let httpClient: any HTTPClientProtocol

    /// Community blocklists (CAPI, lists) can hold tens of thousands of entries:
    /// only local detections and manual bans are asked for.
    public static let origins = "crowdsec,cscli"
    /// Upper bound kept in memory, whatever the server sends.
    public static let maxDecisions = 1000

    public init(baseURL: URL, apiKey: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await decisions()
    }

    /// Active decisions; `null` (none) is an empty list.
    public func decisions(now: Date = .now) async throws -> [CrowdSecDecision] {
        let spec = HTTPRequestSpec(
            method: .get,
            url: endpoint(baseURL, ["v1", "decisions"], query: [URLQueryItem(name: "origins", value: Self.origins)]),
            headers: ["X-Api-Key": apiKey]
        )
        let data = try await httpClient.fetchOK(spec)
        let trimmed = data.drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        if trimmed.isEmpty || trimmed.starts(with: Data("null".utf8)) { return [] }
        let decoder = JSONDecoder()
        decoder.userInfo[.decisionsReferenceDate] = now
        do {
            let list = try decoder.decode(LossyArray<CrowdSecDecision>.self, from: data)
            guard list.elements.count > Self.maxDecisions else { return list.elements }
            // Over the cap: keep the longest remaining, as the inventory sorts them.
            let sorted = list.elements.sorted { ($0.expiresAt ?? .distantFuture) > ($1.expiresAt ?? .distantFuture) }
            return Array(sorted.prefix(Self.maxDecisions))
        } catch {
            throw ServiceProviderError.decodingFailed
        }
    }
}

// MARK: - Nginx Proxy Manager

public enum NPMCredentialError: Error, Sendable, Equatable {
    case invalidFormat
}

/// Nginx Proxy Manager API with a dedicated "View Only" user. The login
/// (`email:password`) stays in the Keychain; the session token obtained from
/// `/api/tokens` is kept in memory until it expires.
public struct NPMClient: Sendable {
    private let baseURL: URL
    private let serviceID: UUID
    private let credential: String
    private let tokenCache: AccessTokenCache
    private let httpClient: any HTTPClientProtocol

    public init(baseURL: URL, serviceID: UUID, credential: String, tokenCache: AccessTokenCache, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.serviceID = serviceID
        self.credential = credential
        self.tokenCache = tokenCache
        self.httpClient = httpClient
    }

    /// `email:password`; the password may contain ":".
    public static func parse(_ credential: String) throws -> (identity: String, secret: String) {
        let parts = credential.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { throw NPMCredentialError.invalidFormat }
        return (String(parts[0]), String(parts[1]))
    }

    public func checkConnection() async throws {
        _ = try await proxyHosts()
    }

    public func proxyHosts() async throws -> [NPMProxyHost] {
        let token = try await accessToken()
        let spec = HTTPRequestSpec(
            method: .get,
            url: endpoint(baseURL, ["api", "nginx", "proxy-hosts"]),
            headers: ["Authorization": "Bearer \(token)"]
        )
        do {
            let list: LossyArray<NPMProxyHost> = try await httpClient.fetchJSON(spec)
            return list.elements
        } catch ServiceProviderError.unauthorized {
            // Session expired early: forget it, no retry.
            await tokenCache.invalidate(serviceID, token: token)
            throw ServiceProviderError.unauthorized
        }
    }

    func accessToken() async throws -> String {
        guard let login = try? Self.parse(credential) else { throw ServiceProviderError.unauthorized }
        let spec = tokenRequest(identity: login.identity, secret: login.secret)
        let httpClient = httpClient
        // The server is part of the key: a session token is never sent to another host.
        return try await tokenCache.token(for: serviceID, credential: Self.tokenCacheKey(baseURL, credential)) {
            try await Self.fetchToken(spec, httpClient: httpClient)
        }
    }

    /// Cache key: the server and the credential, so a token is never reused for
    /// another host or after the credential changed.
    static func tokenCacheKey(_ baseURL: URL, _ credential: String) -> String {
        "\(baseURL.absoluteString)\n\(credential)"
    }

    /// `POST /api/tokens`. POST: never retried.
    func tokenRequest(identity: String, secret: String) -> HTTPRequestSpec {
        let body = (try? JSONSerialization.data(withJSONObject: ["identity": identity, "secret": secret])) ?? Data()
        return HTTPRequestSpec(
            method: .post,
            url: endpoint(baseURL, ["api", "tokens"]),
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    private static func fetchToken(_ spec: HTTPRequestSpec, httpClient: any HTTPClientProtocol, now: Date = .now) async throws -> AccessToken {
        struct Payload: Decodable {
            let token: String?
            let expires: String?
        }
        do {
            let payload: Payload = try await httpClient.fetchJSON(spec)
            guard let token = payload.token, !token.isEmpty else { throw ServiceProviderError.decodingFailed }
            // NPM sessions last 1 day by default; never trust more than that. A date
            // already past (clock skew between phone and server) falls back to 1 hour
            // instead of logging in again on every refresh.
            var stated = payload.expires.flatMap(RFC3339Timestamp.parse) ?? now.addingTimeInterval(3600)
            if stated <= now.addingTimeInterval(5 * 60) { stated = now.addingTimeInterval(3600) }
            let expiresAt = min(stated, now.addingTimeInterval(24 * 3600))
            return AccessToken(value: token, expiresAt: expiresAt)
        } catch ServiceProviderError.unexpectedStatus(let code) where code == 400 {
            // Wrong email or password.
            throw ServiceProviderError.unauthorized
        }
    }
}

// MARK: - AdGuard Home

/// AdGuard Home with a dedicated user (`Authorization: Basic`).
public struct AdGuardClient: Sendable {
    private let baseURL: URL
    private let credential: String
    private let httpClient: any HTTPClientProtocol

    public init(baseURL: URL, credential: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.credential = credential
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await status()
    }

    func status() async throws -> AdGuardStatusPayload {
        try await httpClient.fetchJSON(HTTPRequestSpec(method: .get, url: endpoint(baseURL, ["control", "status"]), headers: basicHeader(credential)))
    }

    func stats() async throws -> AdGuardStatsPayload {
        try await httpClient.fetchJSON(HTTPRequestSpec(method: .get, url: endpoint(baseURL, ["control", "stats"]), headers: basicHeader(credential)))
    }

    /// Sequential: a refused login costs one request.
    public func summary() async throws -> AdGuardSummary {
        let status = try await status()
        let stats = try await stats()
        return AdGuardSummary(
            protectionEnabled: status.protectionEnabled, running: status.running, version: status.version,
            dnsQueries: stats.dnsQueries, blocked: stats.blocked, averageProcessingTime: stats.averageProcessingTime,
            topQueried: stats.topQueried, topBlocked: stats.topBlocked
        )
    }
}
