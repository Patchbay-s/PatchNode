import Foundation

/// How the credential of a service type is typed in the form.
public enum CredentialShape: Sendable, Equatable {
    /// One field (API token, bouncer key, OAuth client…).
    case single
    /// Two fields composed into `user:password` (Basic authentication, or the
    /// e-mail and password of Nginx Proxy Manager).
    case pair(userIsEmail: Bool)
}

extension ServiceKind {
    public var credentialShape: CredentialShape {
        switch self {
        case .dockerSocketProxy, .prometheus, .alertmanager, .adGuardHome, .glances: .pair(userIsEmail: false)
        case .nginxProxyManager: .pair(userIsEmail: true)
        default: .single
        }
    }
}

/// Separate user and password fields, composed into the `user:password` string
/// the providers expect (and the Keychain stores).
public enum CredentialPair {
    public enum Result: Sendable, Equatable {
        /// Both fields empty.
        case empty
        case composed(String)
        /// Only one of the two fields filled.
        case incomplete
        /// Basic authentication can't carry a `:` in the user name.
        case colonInUser
    }

    /// Both values are expected already trimmed (`InputNormalization.credential`).
    public static func compose(user: String, password: String) -> Result {
        switch (user.isEmpty, password.isEmpty) {
        case (true, true): return .empty
        case (false, false):
            return user.contains(":") ? .colonInUser : .composed("\(user):\(password)")
        default: return .incomplete
        }
    }
}

/// Rules for editing a configured service: the type is fixed, the stored
/// credential is never shown (an empty field keeps it), and a new URL or a new
/// credential must pass a connection test before anything is saved.
public struct ServiceEditRules: Sendable, Equatable {
    public let originalName: String
    public let originalURL: String

    public init(originalName: String, originalURL: String) {
        self.originalName = originalName
        self.originalURL = originalURL
    }

    /// `url` is the normalized address (`URL.absoluteString` once valid).
    public func requiresTest(url: String, credentialEntered: Bool) -> Bool {
        url != originalURL || credentialEntered
    }

    public func hasChanges(name: String, url: String, credentialEntered: Bool) -> Bool {
        name != originalName || requiresTest(url: url, credentialEntered: credentialEntered)
    }

    /// A new origin (scheme, host or port) gets no stored credential: a typo or
    /// a look-alike domain would otherwise receive the token without it ever
    /// being typed. A new path on the same server keeps it.
    public func requiresNewCredential(url: String) -> Bool {
        guard let original = URLComponents(string: originalURL), let new = URLComponents(string: url) else {
            return url != originalURL
        }
        return original.scheme?.lowercased() != new.scheme?.lowercased()
            || original.host?.lowercased() != new.host?.lowercased()
            || original.port != new.port
    }

    /// A rename alone needs no test; anything touching the connection does.
    public func canSave(name: String, url: String, credentialEntered: Bool, testPassed: Bool) -> Bool {
        guard !name.isEmpty, hasChanges(name: name, url: url, credentialEntered: credentialEntered) else { return false }
        if requiresNewCredential(url: url) && !credentialEntered { return false }
        return !requiresTest(url: url, credentialEntered: credentialEntered) || testPassed
    }
}
