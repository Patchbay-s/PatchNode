import Foundation
import Crypto
import NIOSSH

/// OpenSSH's fingerprint: `SHA256:` then the base64 (no padding) of the
/// SHA-256 of the key's wire encoding, as `ssh-keygen -lf` prints it.
public enum SSHHostKeyFingerprint {
    public static func of(_ key: NIOSSHPublicKey) -> String {
        let parts = String(openSSHPublicKey: key).split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return "SHA256:?" }
        return of(wireBlob: blob)
    }

    public static func of(wireBlob: Data) -> String {
        let digest = Data(SHA256.hash(data: wireBlob)).base64EncodedString()
        return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
    }

    /// Key type shown with the fingerprint ("ssh-ed25519").
    public static func algorithm(of key: NIOSSHPublicKey) -> String {
        String(openSSHPublicKey: key).split(separator: " ").first.map(String.init) ?? "?"
    }
}
