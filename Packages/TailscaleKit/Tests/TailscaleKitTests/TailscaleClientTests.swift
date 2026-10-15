import Foundation
import Testing
import PatchNodeCore
@testable import TailscaleKit

private typealias F = TailscaleFixtures

/// Decodes an `application/x-www-form-urlencoded` body (no "+" → space: the client
/// percent-encodes "+").
private func formFields(_ body: Data?) -> [String: String] {
    guard let body, let text = String(data: body, encoding: .utf8), !text.isEmpty else { return [:] }
    var fields: [String: String] = [:]
    for pair in text.split(separator: "&", omittingEmptySubsequences: false) {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
        let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? String(parts[1])) : ""
        fields[name] = value
    }
    return fields
}

@Suite("TailscaleCredential")
struct TailscaleCredentialTests {
    @Test func parsesOAuthClientIDAndSecret() throws {
        #expect(try TailscaleCredential(F.oauthCredential) == .oauth(clientID: F.clientID, clientSecret: F.clientSecret))
    }

    @Test func secretMayContainColonsAndSurroundingWhitespaceIsTrimmed() throws {
        let credential = try TailscaleCredential("  fake-id:fake:secret:1234\n")
        #expect(credential == .oauth(clientID: "fake-id", clientSecret: "fake:secret:1234"))
    }

    @Test func parsesAPIAccessToken() throws {
        #expect(try TailscaleCredential(F.apiKey) == .apiKey(F.apiKey))
        #expect(try TailscaleCredential(" \(F.apiKey) \n") == .apiKey(F.apiKey))
    }

    @Test(arguments: ["", "   ", "just-a-string", ":fake-secret", "fake-id:", ":"])
    func rejectsInvalidCredential(raw: String) {
        #expect(throws: TailscaleCredentialError.invalidFormat) { try TailscaleCredential(raw) }
    }
}

@Suite("TailscaleClient")
struct TailscaleClientTests {
    private func routes(
        token: FakeHTTPClient.Outcome = .json(F.tokenResponse),
        devices: FakeHTTPClient.Outcome = .json(F.devicesJSON)
    ) -> FakeHTTPClient {
        FakeHTTPClient(routes: [F.tokenPath: token, F.devicesPath: devices])
    }

    private func client(
        _ fake: FakeHTTPClient, credential: String = F.oauthCredential,
        cache: AccessTokenCache = AccessTokenCache(), baseURL: URL = F.baseURL
    ) -> TailscaleClient {
        TailscaleClient(baseURL: baseURL, serviceID: F.serviceID, credential: credential, tokenCache: cache, httpClient: fake)
    }

    // MARK: OAuth token request

    @Test func oauthFlowPostsFormThenFetchesDevicesWithBearer() async throws {
        let fake = routes()
        let devices = try await client(fake).devices()
        #expect(devices.count == 5)

        let specs = await fake.receivedSpecs
        #expect(specs.map(\.url.path) == [F.tokenPath, F.devicesPath])

        let token = specs[0]
        #expect(token.method == .post)
        #expect(token.url.host == "tailscale-api.example.invalid")
        #expect(token.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(token.headers["Authorization"] == nil)
        #expect(formFields(token.body) == [
            "client_id": F.clientID,
            "client_secret": F.clientSecret,
            "grant_type": "client_credentials",
        ])

        let list = specs[1]
        #expect(list.method == .get)
        #expect(list.headers["Authorization"] == "Bearer \(F.accessToken)")
        #expect(list.body == nil)
    }

    @Test func formBodyEncodesPlusAmpersandAndEqualsInSecret() throws {
        let secret = "fake+secret&grant_type=password 1234%"
        let spec = client(routes()).tokenRequest(clientID: "fake id+1", clientSecret: secret)
        let raw = try #require(spec.body.flatMap { String(data: $0, encoding: .utf8) })
        #expect(!raw.contains("+"))
        #expect(!raw.contains(" "))
        // Exactly three fields: the "&" and "=" of the secret did not split it.
        #expect(raw.split(separator: "&").count == 3)
        #expect(formFields(spec.body) == [
            "client_id": "fake id+1",
            "client_secret": secret,
            "grant_type": "client_credentials",
        ])
    }

    @Test func defaultBaseURLIsThePublicTailscaleAPI() async throws {
        let fake = routes()
        let client = TailscaleClient(serviceID: F.serviceID, credential: F.oauthCredential, tokenCache: AccessTokenCache(), httpClient: fake)
        _ = try await client.devices()
        let urls = await fake.receivedURLs
        #expect(urls.map(\.absoluteString) == [
            "https://api.tailscale.com/api/v2/oauth/token",
            "https://api.tailscale.com/api/v2/tailnet/-/devices",
        ])
    }

    // MARK: Token cache

    @Test func accessTokenIsReusedFromCacheOnSecondCall() async throws {
        let fake = routes()
        let cache = AccessTokenCache()
        let client = client(fake, cache: cache)
        _ = try await client.devices()
        _ = try await client.devices()

        let specs = await fake.receivedSpecs
        #expect(specs.map(\.url.path) == [F.tokenPath, F.devicesPath, F.devicesPath])
        #expect(specs.count { $0.method == .post } == 1)
        #expect(specs[2].headers["Authorization"] == "Bearer \(F.accessToken)")
        #expect(await cache.cachedCount == 1)
    }

    @Test func concurrentCallsShareOneTokenRequest() async throws {
        let fake = routes()
        let client = client(fake)
        async let first = client.devices()
        async let second = client.devices()
        _ = try await (first, second)
        #expect(await fake.receivedSpecs.count { $0.method == .post } == 1)
    }

    @Test func tokenLifetimeIsCappedToOneHour() async throws {
        let fake = routes(token: .json(#"{"access_token":"\#(F.accessToken)","expires_in":86400}"#))
        let cache = AccessTokenCache()
        _ = try await client(fake, cache: cache).devices()

        let refetched = "fake-refetched-token"
        let fetch: @Sendable () async throws -> AccessToken = { AccessToken(value: refetched, expiresAt: .now.addingTimeInterval(7200)) }
        let soon = try await cache.token(for: F.serviceID, credential: TailscaleClient.tokenCacheKey(F.baseURL, F.oauthCredential), now: .now.addingTimeInterval(30 * 60), fetch: fetch)
        #expect(soon == F.accessToken)
        let later = try await cache.token(for: F.serviceID, credential: TailscaleClient.tokenCacheKey(F.baseURL, F.oauthCredential), now: .now.addingTimeInterval(2 * 3600), fetch: fetch)
        #expect(later == refetched)
    }

    @Test func missingExpiresInDefaultsToOneHour() async throws {
        let fake = routes(token: .json(#"{"access_token":"\#(F.accessToken)"}"#))
        let cache = AccessTokenCache()
        _ = try await client(fake, cache: cache).devices()
        let fetch: @Sendable () async throws -> AccessToken = { AccessToken(value: "fake-other", expiresAt: .now) }
        #expect(try await cache.token(for: F.serviceID, credential: TailscaleClient.tokenCacheKey(F.baseURL, F.oauthCredential), now: .now.addingTimeInterval(1800), fetch: fetch) == F.accessToken)
        #expect(try await cache.token(for: F.serviceID, credential: TailscaleClient.tokenCacheKey(F.baseURL, F.oauthCredential), now: .now.addingTimeInterval(3 * 3600), fetch: fetch) == "fake-other")
    }

    // MARK: API key

    @Test func apiKeyIsUsedDirectlyWithoutTokenRequest() async throws {
        let fake = routes()
        let cache = AccessTokenCache()
        let devices = try await client(fake, credential: F.apiKey, cache: cache).devices()
        #expect(devices.count == 5)
        let specs = await fake.receivedSpecs
        #expect(specs.map(\.url.path) == [F.devicesPath])
        #expect(specs[0].headers["Authorization"] == "Bearer \(F.apiKey)")
        #expect(await cache.cachedCount == 0)
    }

    @Test func malformedCredentialIsUnauthorizedWithoutAnyRequest() async throws {
        let fake = routes()
        await #expect(throws: ServiceProviderError.unauthorized) {
            try await client(fake, credential: "not-a-credential").devices()
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    // MARK: Token errors

    @Test func tokenEndpoint400IsUnauthorizedAndNotRetried() async throws {
        let fake = routes(token: .json(#"{"error":"invalid_client","error_description":"fake"}"#, status: 400))
        let cache = AccessTokenCache()
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake, cache: cache).devices() }
        #expect(await fake.receivedPaths == [F.tokenPath])
        #expect(await cache.cachedCount == 0)
    }

    @Test func tokenEndpoint401And403AreNotRetried() async throws {
        for (outcome, expected) in [(FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized), (.forbidden, .forbidden)] {
            let fake = routes(token: outcome)
            await #expect(throws: expected) { try await client(fake).devices() }
            #expect(await fake.receivedPaths == [F.tokenPath])
        }
    }

    @Test func tokenEndpointTimeoutIsUnreachableWithSinglePost() async throws {
        let fake = routes(token: .timeout)
        await #expect(throws: ServiceProviderError.unreachable) { try await client(fake).devices() }
        #expect(await fake.receivedSpecs.map(\.method) == [.post])
    }

    @Test func tokenEndpoint500IsUnexpectedStatus() async throws {
        let fake = routes(token: .serverError)
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) { try await client(fake).devices() }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test(arguments: [
        FakeHTTPClient.Outcome.invalidJSON,
        .emptyBody,
        .json(#"{"token_type":"Bearer","expires_in":3600}"#),
        .json(#"{"access_token":"","expires_in":3600}"#),
    ])
    func unusableTokenResponseIsDecodingFailure(outcome: FakeHTTPClient.Outcome) async throws {
        let fake = routes(token: outcome)
        let cache = AccessTokenCache()
        await #expect(throws: ServiceProviderError.decodingFailed) { try await client(fake, cache: cache).devices() }
        #expect(await fake.receivedPaths == [F.tokenPath])
        #expect(await cache.cachedCount == 0)
    }

    // MARK: Devices errors

    @Test func devices401InvalidatesCachedTokenAndIsNotRetried() async throws {
        let fake = routes(devices: .unauthorized)
        let cache = AccessTokenCache()
        let client = client(fake, cache: cache)
        await #expect(throws: ServiceProviderError.unauthorized) { try await client.devices() }
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
        #expect(await cache.cachedCount == 0)

        // The next (user-requested) refresh asks for a new token.
        await #expect(throws: ServiceProviderError.unauthorized) { try await client.devices() }
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath, F.tokenPath, F.devicesPath])
    }

    @Test func devices403IsForbiddenAndNotRetried() async throws {
        let fake = routes(devices: .forbidden)
        await #expect(throws: ServiceProviderError.forbidden) { try await client(fake).devices() }
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
    }

    @Test func devicesTimeoutIsUnreachable() async throws {
        let fake = routes(devices: .timeout)
        await #expect(throws: ServiceProviderError.unreachable) { try await client(fake).devices() }
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
    }

    @Test func devicesInvalidJSONAndEmptyBodyAreDecodingFailures() async throws {
        for outcome in [FakeHTTPClient.Outcome.invalidJSON, .emptyBody] {
            let fake = routes(devices: outcome)
            await #expect(throws: ServiceProviderError.decodingFailed) { try await client(fake).devices() }
        }
    }

    @Test(arguments: [#"{"devices":null}"#, #"{}"#, #"{"devices":[]}"#])
    func missingOrNullDeviceListIsEmpty(json: String) async throws {
        let fake = routes(devices: .json(json))
        #expect(try await client(fake).devices().isEmpty)
    }

    @Test func checkConnectionFetchesDevices() async throws {
        let fake = routes()
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == [F.tokenPath, F.devicesPath])
    }

    // MARK: Redaction

    @Test func redactedDescriptionNeverContainsSecrets() async throws {
        for credential in [F.oauthCredential, F.apiKey] {
            let fake = routes()
            _ = try await client(fake, credential: credential).devices()
            for spec in await fake.receivedSpecs {
                let description = spec.redactedDescription
                #expect(!description.contains(F.accessToken))
                #expect(!description.contains(F.clientSecret))
                #expect(!description.contains(F.apiKey))
                #expect(!description.contains("fake-token-1234"))
                if spec.headers["Authorization"] != nil {
                    #expect(description.contains("Authorization: <redacted>"))
                }
            }
        }
    }
}
