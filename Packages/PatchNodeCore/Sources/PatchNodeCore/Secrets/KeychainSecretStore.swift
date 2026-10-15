#if canImport(Security)
import Foundation
import Security

/// Stores each secret as a generic password, accessible only when the device is
/// unlocked. By default never synchronized to iCloud Keychain and never migrated
/// to another device (`WhenUnlockedThisDeviceOnly`).
///
/// With the explicit option "Sync tokens with iCloud Keychain" (off by default,
/// `TokenSyncSettings`), new secrets are written as synchronizable items
/// (`WhenUnlocked`: iCloud Keychain refuses `ThisDeviceOnly`), end-to-end
/// encrypted by iCloud Keychain. Reads then prefer the synced item and fall back
/// to a device-only one; with the option off, synced items are ignored.
///
/// Each secret is bound to its server (`kSecAttrLabel` = `CredentialOrigin`,
/// not a secret): `read(for:origin:)` returns nothing for another server, so an
/// address changed through iCloud sync or an imported file never receives the
/// token. Secrets saved by 1.0 have no label: `bindUnlabeled` binds them at the
/// first 1.1 launch, while the configuration is still local.
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let synchronizes: @Sendable () -> Bool
    private let acceptsUnbound: @Sendable () -> Bool

    public init(
        service: String = "fr.antxis.apple.labwatch.secrets",
        synchronizes: @escaping @Sendable () -> Bool = { TokenSyncSettings.isEnabled() },
        acceptsUnbound: @escaping @Sendable () -> Bool = { CredentialBinding.acceptsUnbound() }
    ) {
        self.service = service
        self.synchronizes = synchronizes
        self.acceptsUnbound = acceptsUnbound
    }

    // MARK: - SecretStore

    /// Without an origin: keeps any existing binding. The app saves with
    /// `save(_:for:origin:)`.
    public func save(_ secret: String, for id: UUID) async throws {
        try store(Data(secret.utf8), account: id.uuidString, label: nil)
    }

    public func save(_ secret: String, for id: UUID, origin: String) async throws {
        try store(Data(secret.utf8), account: id.uuidString, label: origin)
    }

    /// Ignores the binding (tests, tools). The app reads with `read(for:origin:)`.
    public func read(for id: UUID) async throws -> String? {
        try firstSecret(account: id.uuidString) { found in
            found.filter(Self.isSynced) + found.filter { !Self.isSynced($0) }
        }
    }

    public func read(for id: UUID, origin: String) async throws -> String? {
        let acceptsUnbound = acceptsUnbound()
        return try firstSecret(account: id.uuidString) { found in
            // A copy saved for this server, the synced one first; an unbound
            // 1.0 copy only until bound.
            let matching = found.filter { Self.label($0) == origin }
            let unbound = acceptsUnbound ? found.filter(isUnbound) : []
            return matching.filter(Self.isSynced) + matching.filter { !Self.isSynced($0) } + unbound
        }
    }

    /// With token sync on, both copies: the service is deleted everywhere. Off,
    /// this device's copy only: a synced copy belongs to devices that sync.
    public func delete(for id: UUID) async throws {
        try remove(account: id.uuidString, synchronizable: synchronizes() ? nil : false)
    }

    public func deleteDeviceOnly(for id: UUID) async throws {
        try remove(account: id.uuidString, synchronizable: false)
    }

    // MARK: - Sync and binding

    /// Moves the secrets of `ids` to iCloud Keychain (`enabled`) or back to this
    /// device only, with their binding. Each one is written at its destination
    /// before its source is deleted: a failure leaves it readable where it was.
    /// Turning sync off deletes those synced copies, hence on the user's other
    /// devices too. Returns how many secrets moved. Call with the setting already
    /// on when enabling (reads look in both places meanwhile), still on when
    /// disabling.
    ///
    /// `keepingSynchronized` (enabling only): services whose existing synced
    /// copy wins over this device's one (`synchronizedConflicts`, the user's
    /// choice): the local copy is deleted, the synced one left as it is.
    @discardableResult
    public func moveAll(toSynchronized enabled: Bool, ids: Set<UUID>, keepingSynchronized: Set<UUID> = []) async throws -> Int {
        let source = !enabled
        var moved = 0
        for item in try items(account: nil, synchronizable: source) {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let id = UUID(uuidString: account), ids.contains(id)
            else { continue }
            if enabled, keepingSynchronized.contains(id), try copy(account: account, synchronizable: true) != nil {
                try remove(account: account, synchronizable: false)
                moved += 1
                continue
            }
            guard let copy = try copy(account: account, synchronizable: source),
                  let data = copy[kSecValueData as String] as? Data
            else { continue }
            // Label and data from the same read: a token saved meanwhile for
            // another server moves with its own binding.
            try write(data, account: account, synchronizable: enabled, label: isUnbound(copy) ? nil : Self.label(copy))
            try remove(account: account, synchronizable: source)
            moved += 1
        }
        return moved
    }

    /// Services of `ids` whose token on this device differs from a copy already
    /// in iCloud Keychain (saved by another device, for the same or another
    /// server): turning sync on would replace that copy everywhere, so the user
    /// chooses first.
    public func synchronizedConflicts(ids: Set<UUID>) async throws -> Set<UUID> {
        // Usually nothing synced yet (first activation): two listings, no read.
        let synced = Set(try items(account: nil, synchronizable: true).compactMap { $0[kSecAttrAccount as String] as? String })
        guard !synced.isEmpty else { return [] }
        var conflicts = Set<UUID>()
        for item in try items(account: nil, synchronizable: false) {
            guard let account = item[kSecAttrAccount as String] as? String, synced.contains(account),
                  let id = UUID(uuidString: account), ids.contains(id),
                  let local = try copy(account: account, synchronizable: false),
                  let synced = try copy(account: account, synchronizable: true)
            else { continue }
            let sameData = (local[kSecValueData as String] as? Data) == (synced[kSecValueData as String] as? Data)
            let sameBinding = (isUnbound(local) ? nil : Self.label(local)) == (isUnbound(synced) ? nil : Self.label(synced))
            if !sameData || !sameBinding { conflicts.insert(id) }
        }
        return conflicts
    }

    /// Deletes every secret of this app from iCloud Keychain, on all the user's
    /// devices ("Delete my iCloud data"). Device-only copies stay. Returns how
    /// many went.
    @discardableResult
    public func deleteAllSynchronized() async throws -> Int {
        let count = try items(account: nil, synchronizable: true).count
        guard count > 0 else { return 0 }
        let status = SecItemDelete(baseQuery(account: nil, synchronizable: true) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.deleteFailed(status)
        }
        return count
    }

    /// Binds every secret saved without a server (1.0) to the current address of
    /// its service. Run while the configuration is local (sync off), then
    /// `CredentialBinding.markDone()`: from then on an unbound secret is never sent.
    public func bindUnlabeled(origins: [UUID: String]) async throws {
        for item in try items(account: nil, synchronizable: nil) where isUnbound(item) {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let id = UUID(uuidString: account), let origin = origins[id]
            else { continue }
            let status = SecItemUpdate(
                baseQuery(account: account, synchronizable: Self.isSynced(item)) as CFDictionary,
                [kSecAttrLabel as String: origin] as CFDictionary
            )
            guard status == errSecSuccess else { throw SecretStoreError.saveFailed(status) }
        }
    }

    // MARK: - Keychain

    /// Update in place, add only if missing: never deletes first, so a failed
    /// write can't lose the previous secret. With sync on, the device-only copy
    /// goes once the synced one is written.
    private func store(_ data: Data, account: String, label: String?) throws {
        let synced = synchronizes()
        try write(data, account: account, synchronizable: synced, label: label)
        if synced {
            try remove(account: account, synchronizable: false)
        }
    }

    private func write(_ data: Data, account: String, synchronizable: Bool, label: String?) throws {
        let query = baseQuery(account: account, synchronizable: synchronizable)
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: synchronizable ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let label { attributes[kSecAttrLabel as String] = label }
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.saveFailed(updateStatus)
        }
        let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.saveFailed(addStatus)
        }
    }

    /// The secret of the first of `candidates` (ordered from the copies of
    /// `account`) still in the Keychain. Each copy is read with its attributes
    /// and checked against `candidates` again, so its binding is verified on
    /// what is actually returned. With sync on, both copies are listed in one
    /// query; if every candidate vanished before its data was read (`moveAll`
    /// deletes the source after writing the destination), the copies are
    /// listed again once, so a secret being moved never looks missing. Off, the
    /// local copy only.
    private func firstSecret(
        account: String,
        candidates: ([[String: Any]]) -> [[String: Any]]
    ) throws -> String? {
        for _ in 0..<2 {
            let ordered = candidates(try items(account: account, synchronizable: synchronizes() ? nil : false))
            if ordered.isEmpty { return nil }
            for item in ordered {
                if let copy = try copy(account: account, synchronizable: Self.isSynced(item)),
                   !candidates([copy]).isEmpty,
                   let data = copy[kSecValueData as String] as? Data {
                    return String(data: data, encoding: .utf8)
                }
            }
        }
        return nil
    }

    /// The attributes of the matching items, without their data: macOS refuses
    /// `kSecReturnData` with `kSecMatchLimitAll` (errSecParam), so the data is
    /// read copy by copy with `copy(account:synchronizable:)`. `synchronizable`
    /// nil: both copies.
    private func items(account: String?, synchronizable: Bool?) throws -> [[String: Any]] {
        var query = baseQuery(account: account, synchronizable: synchronizable ?? false)
        if synchronizable == nil { query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny }
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw SecretStoreError.readFailed(status)
        }
        return items
    }

    /// `synchronizable` nil: both copies.
    private func remove(account: String, synchronizable: Bool?) throws {
        var query = baseQuery(account: account, synchronizable: synchronizable ?? false)
        if synchronizable == nil { query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.deleteFailed(status)
        }
    }

    /// One copy with its attributes and data (service, account and
    /// synchronizable identify it), nil if it is gone.
    private func copy(account: String, synchronizable: Bool) throws -> [String: Any]? {
        var query = baseQuery(account: account, synchronizable: synchronizable)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item = result as? [String: Any] else {
            throw SecretStoreError.readFailed(status)
        }
        return item
    }

    private static func label(_ item: [String: Any]) -> String? {
        item[kSecAttrLabel as String] as? String
    }

    /// Saved without a server (1.0). iOS returns no label; macOS fills it with
    /// the service name, which is never a `CredentialOrigin` (https://host:port).
    private func isUnbound(_ item: [String: Any]) -> Bool {
        let label = Self.label(item)
        return label == nil || label == service
    }

    private static func isSynced(_ item: [String: Any]) -> Bool {
        (item[kSecAttrSynchronizable as String] as? Bool) == true
    }

    private func baseQuery(account: String?, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }
}
#endif
