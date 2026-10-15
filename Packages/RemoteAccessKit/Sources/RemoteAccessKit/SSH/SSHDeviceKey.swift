import Foundation
import Crypto
import NIOSSH
import PatchNodeCore

/// This device's SSH key: ed25519, generated here, one per device. The
/// private half lives only in the Keychain (`WhenUnlockedThisDeviceOnly`,
/// never synchronized, even with the iCloud Keychain option), and never
/// leaves the app: only the public key is shown and copied.
public struct SSHDeviceKey: Sendable {
    /// Keychain service of SSH secrets, separate from the service tokens (the
    /// token sync option never touches it).
    public static let keychainService = "fr.antxis.apple.labwatch.ssh"
    static let account = UUID(uuidString: "6B3F2C1E-5A4D-4E8F-9C2B-1D0E7F6A5B4C")!
    static let origin = "ssh-device-key"

    public let privateKey: Curve25519.Signing.PrivateKey

    /// The store the app uses: dedicated service, never synchronized.
    #if canImport(Security)
    public static func keychain() -> any SecretStore {
        KeychainSecretStore(service: keychainService, synchronizes: { false }, acceptsUnbound: { false })
    }
    #endif

    public static func load(from store: any SecretStore) async throws -> SSHDeviceKey? {
        guard let encoded = try await store.read(for: account, origin: origin),
              let raw = Data(base64Encoded: encoded),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        else { return nil }
        return SSHDeviceKey(privateKey: key)
    }

    /// The existing key, or a new one saved first.
    public static func loadOrCreate(in store: any SecretStore) async throws -> SSHDeviceKey {
        if let existing = try await load(from: store) { return existing }
        let key = Curve25519.Signing.PrivateKey()
        try await store.save(key.rawRepresentation.base64EncodedString(), for: account, origin: origin)
        return SSHDeviceKey(privateKey: key)
    }

    /// Removes the key: every server that trusted it must get the new one.
    public static func delete(from store: any SecretStore) async throws {
        try await store.delete(for: account)
    }

    /// `ssh-ed25519 AAAA… comment`.
    public func openSSHPublicKey(comment: String) -> String {
        let key = String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: privateKey).publicKey)
        let cleaned = comment.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "-_.@".unicodeScalars.contains($0) }
        return cleaned.isEmpty ? key : key + " " + String(String.UnicodeScalarView(cleaned))
    }

    public var fingerprint: String {
        SSHHostKeyFingerprint.of(NIOSSHPrivateKey(ed25519Key: privateKey).publicKey)
    }
}

/// The line to add to `~/.ssh/authorized_keys`, with the options that limit
/// what the key can do (no forwarding of any kind) and, if given, the
/// addresses it may come from.
public enum AuthorizedKeysLine {
    public enum Failure: Error, Equatable { case invalidSource }

    /// Everything off (forwarding of any kind, ~/.ssh/rc, and whatever future
    /// OpenSSH versions add), then the terminal back on.
    public static let restrictions = "restrict,pty"

    /// `from` takes comma-separated addresses or CIDR ranges (`100.64.0.0/10`):
    /// only those characters are accepted, so nothing else can be injected
    /// into the options.
    public static func make(publicKey: String, from sources: String?, restricted: Bool) throws -> String {
        var options: [String] = []
        if let sources = sources?.trimmingCharacters(in: .whitespaces), !sources.isEmpty {
            let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF.:/,*?")
            guard sources.unicodeScalars.allSatisfy(allowed.contains), sources.count <= 200 else { throw Failure.invalidSource }
            options.append("from=\"\(sources)\"")
        }
        if restricted { options.append(restrictions) }
        return options.isEmpty ? publicKey : options.joined(separator: ",") + " " + publicKey
    }
}
