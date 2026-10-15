import Foundation
import PatchNodeCore

public enum TailscaleCredentialError: Error, Sendable, Equatable {
    /// Neither `client-id:client-secret` nor an API access token (`tskey-api-…`).
    case invalidFormat
}

/// How the app authenticates to the Tailscale API.
public enum TailscaleCredential: Sendable, Equatable {
    /// OAuth client (scope `devices:core:read`): exchanged for a 1-hour access token.
    case oauth(clientID: String, clientSecret: String)
    /// API access token (`tskey-api-…`), used as-is.
    case apiKey(String)

    /// `client-id:client-secret`, or an API access token on its own.
    public init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("tskey-api-") {
            self = .apiKey(trimmed)
            return
        }
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw TailscaleCredentialError.invalidFormat
        }
        self = .oauth(clientID: String(parts[0]), clientSecret: String(parts[1]))
    }
}

/// Tailscale API client (`https://api.tailscale.com/api/v2`). The only request the
/// app sends outside the user's private network.
///
/// The OAuth access token is kept in memory only (`AccessTokenCache`) until it
/// expires; the client secret stays in the Keychain.
public struct TailscaleClient: Sendable {
    /// The public Tailscale API: not installation-specific.
    public static let defaultBaseURL = URL(string: "https://api.tailscale.com")!

    private let baseURL: URL
    private let serviceID: UUID
    private let credential: String
    private let tokenCache: AccessTokenCache
    private let httpClient: any HTTPClientProtocol

    public init(
        baseURL: URL = TailscaleClient.defaultBaseURL, serviceID: UUID, credential: String,
        tokenCache: AccessTokenCache, httpClient: any HTTPClientProtocol = HTTPClient()
    ) {
        self.baseURL = baseURL
        self.serviceID = serviceID
        self.credential = credential
        self.tokenCache = tokenCache
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await devices()
    }

    /// Devices of the tailnet the credential belongs to (`-`).
    public func devices() async throws -> [TailscaleDevice] {
        struct Payload: Decodable { let devices: LossyArray<TailscaleDevice>? }
        let token = try await accessToken()
        let spec = HTTPRequestSpec(
            method: .get,
            url: url(["api", "v2", "tailnet", "-", "devices"]),
            headers: ["Authorization": "Bearer \(token)"]
        )
        do {
            let payload: Payload = try await httpClient.fetchJSON(spec)
            return payload.devices?.elements ?? []
        } catch ServiceProviderError.unauthorized {
            // Token revoked early: forget it. No retry (401 bursts are banned);
            // the next refresh, if the user asks for one, gets a new token.
            await tokenCache.invalidate(serviceID, token: token)
            throw ServiceProviderError.unauthorized
        }
    }

    // MARK: - OAuth

    func accessToken() async throws -> String {
        let parsed: TailscaleCredential
        do {
            parsed = try TailscaleCredential(credential)
        } catch {
            // A malformed credential is a refused credential for the UI.
            throw ServiceProviderError.unauthorized
        }
        switch parsed {
        case .apiKey(let key):
            return key
        case .oauth(let clientID, let clientSecret):
            let spec = tokenRequest(clientID: clientID, clientSecret: clientSecret)
            let httpClient = httpClient
            // The server is part of the key: a token is never sent to another host.
            return try await tokenCache.token(for: serviceID, credential: Self.tokenCacheKey(baseURL, credential)) {
                try await Self.fetchToken(spec, httpClient: httpClient)
            }
        }
    }

    /// Cache key: the server and the credential, so a token is never reused for
    /// another host or after the credential changed.
    static func tokenCacheKey(_ baseURL: URL, _ credential: String) -> String {
        "\(baseURL.absoluteString)\n\(credential)"
    }

    /// `POST /api/v2/oauth/token` (client credentials). POST: never retried.
    func tokenRequest(clientID: String, clientSecret: String) -> HTTPRequestSpec {
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials"),
        ]
        // Form encoding: "+" and "&" must not survive unescaped in a secret.
        let body = (form.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return HTTPRequestSpec(
            method: .post,
            url: url(["api", "v2", "oauth", "token"]),
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8)
        )
    }

    private static func fetchToken(_ spec: HTTPRequestSpec, httpClient: any HTTPClientProtocol, now: Date = .now) async throws -> AccessToken {
        struct Payload: Decodable {
            let accessToken: String?
            let expiresIn: Double?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
            }
        }
        do {
            let payload: Payload = try await httpClient.fetchJSON(spec)
            guard let token = payload.accessToken, !token.isEmpty else { throw ServiceProviderError.decodingFailed }
            // Tailscale tokens last 1 hour; stay within that if the field is missing.
            // At least 5 minutes, so a short stated lifetime still gets cached
            // instead of costing a POST per refresh.
            let lifetime = min(max(payload.expiresIn ?? 3600, 300), 3600)
            return AccessToken(value: token, expiresAt: now.addingTimeInterval(lifetime))
        } catch ServiceProviderError.unexpectedStatus(let code) where code == 400 {
            // `invalid_client`: wrong client ID or secret.
            throw ServiceProviderError.unauthorized
        }
    }

    private func url(_ segments: [String]) -> URL {
        var url = baseURL
        for segment in segments {
            url = url.appending(component: segment)
        }
        return url
    }
}
