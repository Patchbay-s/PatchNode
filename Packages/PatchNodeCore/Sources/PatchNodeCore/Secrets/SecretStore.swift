import Foundation

public protocol SecretStore: Sendable {
    func save(_ secret: String, for id: UUID) async throws
    func read(for id: UUID) async throws -> String?
    func delete(for id: UUID) async throws

    /// Saves the secret bound to the server it belongs to (`CredentialOrigin`).
    func save(_ secret: String, for id: UUID, origin: String) async throws
    /// The secret only if it was saved for this origin: a service whose address
    /// changed elsewhere (iCloud sync, an imported file) never sends its token
    /// to the new server.
    func read(for id: UUID, origin: String) async throws -> String?
    /// Removes this device's own copy only, never a copy synced through iCloud
    /// Keychain (which would vanish from the user's other devices too).
    func deleteDeviceOnly(for id: UUID) async throws
}

/// The server a credential belongs to: scheme, host and port, as
/// `ServiceEditRules.requiresNewCredential` compares them. Not a secret.
public enum CredentialOrigin {
    public static func of(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : nil)
        return "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    public static func of(_ string: String) -> String? {
        URL(string: string).flatMap(of)
    }
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case saveFailed(Int32)
    case readFailed(Int32)
    case deleteFailed(Int32)
}
