import Foundation
import Testing
@testable import PatchNodeCore
#if canImport(Security)
import Security
#endif

struct InMemorySecretStoreTests {
    @Test func saveThenReadReturnsSecret() async throws {
        let store = InMemorySecretStore()
        let id = UUID()
        try await store.save("fake-token-1234", for: id)
        #expect(try await store.read(for: id) == "fake-token-1234")
    }

    @Test func readOfUnknownIDReturnsNil() async throws {
        let store = InMemorySecretStore()
        #expect(try await store.read(for: UUID()) == nil)
    }

    @Test func deleteRemovesSecret() async throws {
        let store = InMemorySecretStore()
        let id = UUID()
        try await store.save("fake-token-1234", for: id)
        try await store.delete(for: id)
        #expect(try await store.read(for: id) == nil)
    }

    @Test func deleteOnlyRemovesTargetedSecret() async throws {
        let store = InMemorySecretStore()
        let kept = UUID()
        let removed = UUID()
        try await store.save("fake-token-kept", for: kept)
        try await store.save("fake-token-removed", for: removed)
        try await store.delete(for: removed)
        #expect(try await store.read(for: kept) == "fake-token-kept")
        #expect(try await store.read(for: removed) == nil)
    }

    @Test func saveTwiceOverwritesPreviousSecret() async throws {
        let store = InMemorySecretStore()
        let id = UUID()
        try await store.save("fake-token-old", for: id)
        try await store.save("fake-token-new", for: id)
        #expect(try await store.read(for: id) == "fake-token-new")
    }

    @Test func deleteOfUnknownIDDoesNotThrow() async throws {
        let store = InMemorySecretStore()
        try await store.delete(for: UUID())
    }
}

#if canImport(Security)
struct KeychainSecretStoreTests {
    private func makeStore(acceptsUnbound: Bool = true) -> KeychainSecretStore {
        // Device-only items: the tests never depend on the runner's iCloud
        // Keychain setting.
        KeychainSecretStore(
            service: "fr.antxis.apple.labwatch.tests.\(UUID().uuidString)",
            synchronizes: { false }, acceptsUnbound: { acceptsUnbound }
        )
    }

    @Test func tokenIsOnlyReadForItsOwnServer() async throws {
        let store = makeStore()
        let id = UUID()
        defer { Task { try? await store.delete(for: id) } }
        try await store.save("fake-token-1234", for: id, origin: "https://proxmox.example.invalid:8006")
        #expect(try await store.read(for: id, origin: "https://proxmox.example.invalid:8006") == "fake-token-1234")
        #expect(try await store.read(for: id, origin: "https://evil.example.invalid:443") == nil)
    }

    @Test func unboundTokensAreUsedOnlyUntilBound() async throws {
        let id = UUID()
        let service = "fr.antxis.apple.labwatch.tests.\(UUID().uuidString)"
        let legacy = KeychainSecretStore(service: service, synchronizes: { false }, acceptsUnbound: { true })
        let bound = KeychainSecretStore(service: service, synchronizes: { false }, acceptsUnbound: { false })
        defer { Task { try? await legacy.delete(for: id) } }
        try await legacy.save("fake-token-1234", for: id)
        #expect(try await legacy.read(for: id, origin: "https://a.example.invalid:443") == "fake-token-1234")
        #expect(try await bound.read(for: id, origin: "https://a.example.invalid:443") == nil)
        try await legacy.bindUnlabeled(origins: [id: "https://a.example.invalid:443"])
        #expect(try await bound.read(for: id, origin: "https://a.example.invalid:443") == "fake-token-1234")
        #expect(try await bound.read(for: id, origin: "https://b.example.invalid:443") == nil)
    }

    /// An item exactly as 1.0/1.0.1 wrote it (same service and account, no
    /// label) stays readable, then is bound to its server.
    @Test func tokenSavedBy101IsReadThenBound() async throws {
        let id = UUID()
        let service = "fr.antxis.apple.labwatch.tests.\(UUID().uuidString)"
        let legacy = KeychainSecretStore(service: service, synchronizes: { false }, acceptsUnbound: { true })
        let bound = KeychainSecretStore(service: service, synchronizes: { false }, acceptsUnbound: { false })
        defer { Task { try? await legacy.delete(for: id) } }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecValueData as String: Data("fake-token-101".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        #expect(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)
        #expect(try await legacy.read(for: id) == "fake-token-101")
        #expect(try await legacy.read(for: id, origin: "https://a.example.invalid:443") == "fake-token-101")
        try await legacy.bindUnlabeled(origins: [id: "https://a.example.invalid:443"])
        #expect(try await bound.read(for: id, origin: "https://a.example.invalid:443") == "fake-token-101")
        #expect(try await bound.read(for: id, origin: "https://b.example.invalid:443") == nil)
    }

    @Test func deviceOnlyDeleteRemovesTheLocalCopy() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.save("fake-token-1234", for: id, origin: "https://a.example.invalid:443")
        try await store.deleteDeviceOnly(for: id)
        #expect(try await store.read(for: id) == nil)
    }

    @Test func saveThenReadReturnsSecret() async throws {
        let store = makeStore()
        let id = UUID()
        defer { Task { try? await store.delete(for: id) } }
        try await store.save("fake-token-1234", for: id)
        #expect(try await store.read(for: id) == "fake-token-1234")
        try await store.delete(for: id)
    }

    @Test func readOfUnknownIDReturnsNil() async throws {
        let store = makeStore()
        #expect(try await store.read(for: UUID()) == nil)
    }

    @Test func deleteRemovesSecret() async throws {
        let store = makeStore()
        let id = UUID()
        defer { Task { try? await store.delete(for: id) } }
        try await store.save("fake-token-1234", for: id)
        try await store.delete(for: id)
        #expect(try await store.read(for: id) == nil)
    }

    @Test func saveTwiceOverwritesPreviousSecret() async throws {
        let store = makeStore()
        let id = UUID()
        defer { Task { try? await store.delete(for: id) } }
        try await store.save("fake-token-old", for: id)
        try await store.save("fake-token-new", for: id)
        #expect(try await store.read(for: id) == "fake-token-new")
        try await store.delete(for: id)
    }

    @Test func deleteOfUnknownIDDoesNotThrow() async throws {
        let store = makeStore()
        try await store.delete(for: UUID())
    }
}
#endif
