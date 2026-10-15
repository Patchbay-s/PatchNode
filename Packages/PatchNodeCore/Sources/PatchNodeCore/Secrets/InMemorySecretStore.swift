import Foundation

public actor InMemorySecretStore: SecretStore {
    private var storage: [UUID: String] = [:]
    private var origins: [UUID: String] = [:]

    public init() {}

    public func save(_ secret: String, for id: UUID) async throws {
        storage[id] = secret
    }

    public func save(_ secret: String, for id: UUID, origin: String) async throws {
        storage[id] = secret
        origins[id] = origin
    }

    public func read(for id: UUID) async throws -> String? {
        storage[id]
    }

    /// Like the Keychain: nothing for another server; an unbound secret is used.
    public func read(for id: UUID, origin: String) async throws -> String? {
        guard origins[id] == nil || origins[id] == origin else { return nil }
        return storage[id]
    }

    public func delete(for id: UUID) async throws {
        storage.removeValue(forKey: id)
        origins.removeValue(forKey: id)
    }

    public func deleteDeviceOnly(for id: UUID) async throws {
        try await delete(for: id)
    }
}
