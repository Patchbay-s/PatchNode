import Foundation
import Testing
import PatchNodeCore
@testable import SecurityKit

private typealias F = SecurityFixtures

@Suite("NPMClient")
struct NPMClientTests {
    private func routes(
        token: FakeHTTPClient.Outcome = .json(F.npmTokenResponse()),
        hosts: FakeHTTPClient.Outcome = .json(F.proxyHostsJSON)
    ) -> FakeHTTPClient {
        FakeHTTPClient(routes: [F.tokensPath: token, F.proxyHostsPath: hosts])
    }

    private func client(_ fake: FakeHTTPClient, credential: String = F.npmCredential, cache: AccessTokenCache = AccessTokenCache()) -> NPMClient {
        NPMClient(baseURL: F.npmURL, serviceID: F.serviceID, credential: credential, tokenCache: cache, httpClient: fake)
    }

    // MARK: Credential

    @Test func parsesEmailAndPasswordContainingColons() throws {
        let login = try NPMClient.parse(F.npmCredential)
        #expect(login.identity == F.npmIdentity)
        #expect(login.secret == F.npmPassword)
    }

    @Test(arguments: ["", "no-colon", ":fake-pass", "viewer@example.invalid:", ":"])
    func rejectsInvalidCredential(raw: String) {
        #expect(throws: NPMCredentialError.invalidFormat) { try NPMClient.parse(raw) }
    }

    @Test func invalidCredentialIsUnauthorizedWithoutAnyRequest() async throws {
        let fake = routes()
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake, credential: "no-colon").proxyHosts() }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    // MARK: Login + hosts

    @Test func logsInWithJSONThenFetchesHostsWithBearer() async throws {
        let fake = routes()
        let hosts = try await client(fake).proxyHosts()
        #expect(hosts.count == 4)

        let specs = await fake.receivedSpecs
        #expect(specs.map(\.url.path) == [F.tokensPath, F.proxyHostsPath])

        let login = specs[0]
        #expect(login.method == .post)
        #expect(login.url.host == "npm.example.invalid")
        #expect(login.headers["Content-Type"] == "application/json")
        #expect(login.headers["Authorization"] == nil)
        let body = try #require(login.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == ["identity": F.npmIdentity, "secret": F.npmPassword])

        let list = specs[1]
        #expect(list.method == .get)
        #expect(list.headers["Authorization"] == "Bearer \(F.npmToken)")
    }

    @Test func tokenIsCachedAcrossCalls() async throws {
        let fake = routes()
        let cache = AccessTokenCache()
        let client = client(fake, cache: cache)
        _ = try await client.proxyHosts()
        _ = try await client.proxyHosts()
        #expect(await fake.receivedPaths == [F.tokensPath, F.proxyHostsPath, F.proxyHostsPath])
        #expect(await fake.receivedSpecs.count { $0.method == .post } == 1)
        #expect(await cache.cachedCount == 1)
    }

    @Test func tokenExpiryIsCappedTo24Hours() async throws {
        let cache = AccessTokenCache()
        _ = try await client(routes(), cache: cache).proxyHosts()
        let fetch: @Sendable () async throws -> AccessToken = { AccessToken(value: "fake-refetched", expiresAt: .distantFuture) }
        #expect(try await cache.token(for: F.serviceID, credential: NPMClient.tokenCacheKey(F.npmURL, F.npmCredential), now: .now.addingTimeInterval(23 * 3600), fetch: fetch) == F.npmToken)
        #expect(try await cache.token(for: F.serviceID, credential: NPMClient.tokenCacheKey(F.npmURL, F.npmCredential), now: .now.addingTimeInterval(25 * 3600), fetch: fetch) == "fake-refetched")
    }

    @Test func missingExpiryDefaultsToOneHour() async throws {
        let cache = AccessTokenCache()
        _ = try await client(routes(token: .json(F.npmTokenResponse(expires: nil))), cache: cache).proxyHosts()
        let fetch: @Sendable () async throws -> AccessToken = { AccessToken(value: "fake-refetched", expiresAt: .distantFuture) }
        #expect(try await cache.token(for: F.serviceID, credential: NPMClient.tokenCacheKey(F.npmURL, F.npmCredential), now: .now.addingTimeInterval(1800), fetch: fetch) == F.npmToken)
        #expect(try await cache.token(for: F.serviceID, credential: NPMClient.tokenCacheKey(F.npmURL, F.npmCredential), now: .now.addingTimeInterval(2 * 3600), fetch: fetch) == "fake-refetched")
    }

    @Test func expiryAlreadyPastFallsBackToOneHour() async throws {
        let cache = AccessTokenCache()
        _ = try await client(routes(token: .json(F.npmTokenResponse(expires: "2000-01-01T00:00:00.000Z"))), cache: cache).proxyHosts()
        #expect(await cache.cachedCount == 1)
        let fetch: @Sendable () async throws -> AccessToken = { AccessToken(value: "fake-refetched", expiresAt: .distantFuture) }
        #expect(try await cache.token(for: F.serviceID, credential: NPMClient.tokenCacheKey(F.npmURL, F.npmCredential), now: .now.addingTimeInterval(1800), fetch: fetch) == F.npmToken)
        #expect(try await cache.token(for: F.serviceID, credential: NPMClient.tokenCacheKey(F.npmURL, F.npmCredential), now: .now.addingTimeInterval(2 * 3600), fetch: fetch) == "fake-refetched")
    }

    // MARK: Login errors

    @Test func login400IsUnauthorizedAndNotRetried() async throws {
        let fake = routes(token: .json(#"{"error":{"code":400,"message":"Invalid email or password"}}"#, status: 400))
        let cache = AccessTokenCache()
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake, cache: cache).proxyHosts() }
        #expect(await fake.receivedPaths == [F.tokensPath])
        #expect(await cache.cachedCount == 0)
    }

    @Test func login401And403AreDistinctAndNotRetried() async throws {
        for (outcome, expected) in [(FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized), (.forbidden, .forbidden)] {
            let fake = routes(token: outcome)
            await #expect(throws: expected) { try await client(fake).proxyHosts() }
            #expect(await fake.receivedPaths == [F.tokensPath])
        }
    }

    @Test func loginTimeoutIsUnreachableWithSinglePost() async throws {
        let fake = routes(token: .timeout)
        await #expect(throws: ServiceProviderError.unreachable) { try await client(fake).proxyHosts() }
        #expect(await fake.receivedSpecs.map(\.method) == [.post])
    }

    @Test(arguments: [FakeHTTPClient.Outcome.invalidJSON, .emptyBody, .json(#"{"expires":"2099-01-01T00:00:00.000Z"}"#), .json(#"{"token":""}"#)])
    func unusableLoginResponseIsDecodingFailure(outcome: FakeHTTPClient.Outcome) async throws {
        let fake = routes(token: outcome)
        let cache = AccessTokenCache()
        await #expect(throws: ServiceProviderError.decodingFailed) { try await client(fake, cache: cache).proxyHosts() }
        #expect(await fake.receivedPaths == [F.tokensPath])
        #expect(await cache.cachedCount == 0)
    }

    // MARK: Hosts errors

    @Test func hosts401InvalidatesCachedTokenAndIsNotRetried() async throws {
        let fake = routes(hosts: .unauthorized)
        let cache = AccessTokenCache()
        await #expect(throws: ServiceProviderError.unauthorized) { try await client(fake, cache: cache).proxyHosts() }
        #expect(await fake.receivedPaths == [F.tokensPath, F.proxyHostsPath])
        #expect(await cache.cachedCount == 0)
    }

    @Test func hosts403IsForbiddenAndNotRetried() async throws {
        let fake = routes(hosts: .forbidden)
        await #expect(throws: ServiceProviderError.forbidden) { try await client(fake).proxyHosts() }
        #expect(await fake.receivedPaths == [F.tokensPath, F.proxyHostsPath])
    }

    @Test func hostsTimeoutIsUnreachable() async throws {
        let fake = routes(hosts: .timeout)
        await #expect(throws: ServiceProviderError.unreachable) { try await client(fake).proxyHosts() }
        #expect(await fake.receivedPaths == [F.tokensPath, F.proxyHostsPath])
    }

    @Test func hostsInvalidJSONAndEmptyBodyAreDecodingFailures() async throws {
        for outcome in [FakeHTTPClient.Outcome.invalidJSON, .emptyBody, .json(#"{"error":"not a list"}"#)] {
            await #expect(throws: ServiceProviderError.decodingFailed) { try await client(routes(hosts: outcome)).proxyHosts() }
        }
    }

    @Test func emptyHostList() async throws {
        #expect(try await client(routes(hosts: .json("[]"))).proxyHosts().isEmpty)
    }

    @Test func checkConnectionFetchesHosts() async throws {
        let fake = routes()
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == [F.tokensPath, F.proxyHostsPath])
    }

    // MARK: Redaction

    @Test func redactedDescriptionNeverContainsTokenOrPassword() async throws {
        let fake = routes()
        _ = try await client(fake).proxyHosts()
        for spec in await fake.receivedSpecs {
            let description = spec.redactedDescription
            #expect(!description.contains(F.npmToken))
            #expect(!description.contains(F.npmPassword))
            #expect(!description.contains("fake-npm"))
        }
        #expect(await fake.receivedSpecs.last?.redactedDescription.contains("Authorization: <redacted>") == true)
    }
}

@Suite("NPMProxyHost decoding")
struct NPMProxyHostTests {
    private func hosts() throws -> [NPMProxyHost] {
        try JSONDecoder().decode(LossyArray<NPMProxyHost>.self, from: Data(F.proxyHostsJSON.utf8)).elements
    }

    @Test func decodesRealisticHostAndDropsMalformedOne() throws {
        let hosts = try hosts()
        #expect(hosts.map(\.id) == [1, 2, 3, 7])

        let cloud = hosts[0]
        #expect(cloud.domainNames == ["cloud.example.invalid", "www.cloud.example.invalid"])
        #expect(cloud.title == "cloud.example.invalid")
        #expect(cloud.forwardScheme == "http")
        #expect(cloud.forwardHost == "192.0.2.10")
        #expect(cloud.forwardPort == 8080)
        #expect(cloud.destination == "http://192.0.2.10:8080")
        #expect(cloud.enabled)
        #expect(cloud.hasCertificate)
        #expect(cloud.sslForced)
        #expect(cloud.nginxOnline == true)
        #expect(cloud.nginxError == nil)
        #expect(!cloud.isFailing)
    }

    @Test func boolEnabledAndNginxErrorMakeAFailingHost() throws {
        let broken = try hosts()[1]
        #expect(broken.enabled)
        #expect(!broken.hasCertificate)
        #expect(!broken.sslForced)
        #expect(broken.nginxOnline == false)
        #expect(broken.nginxError == #"nginx: [emerg] host not found in upstream "gone.example.invalid""#)
        #expect(broken.isFailing)
    }

    @Test func disabledHostIsNotFailingAndEmptyErrorIsNil() throws {
        let archive = try hosts()[2]
        #expect(!archive.enabled)
        #expect(archive.nginxOnline == false)
        #expect(archive.nginxError == nil)
        #expect(!archive.isFailing)
    }

    @Test func stringNumbersAndMissingMeta() throws {
        let app = try hosts()[3]
        #expect(app.id == 7)
        #expect(app.forwardPort == 3000)
        #expect(app.forwardScheme == nil)
        #expect(app.destination == "192.0.2.70:3000")
        #expect(app.enabled)
        #expect(app.nginxOnline == nil)
        #expect(!app.isFailing)
    }

    @Test func titleAndDestinationFallbacks() {
        let bare = NPMProxyHost(id: 42, domainNames: [])
        #expect(bare.title == "#42")
        #expect(bare.destination == nil)
        #expect(NPMProxyHost(id: 1, domainNames: [], forwardHost: "").destination == nil)
    }
}
