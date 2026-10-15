import Foundation

public enum ServiceURLValidationError: Error, Sendable, Equatable {
    case notHTTPS
    case invalidURL
    /// `user:password@` in the URL: secrets belong in the token field (Keychain),
    /// never in the URL, which is persisted in SwiftData and shown on screen.
    case containsCredentials
}

public func validateServiceURL(_ raw: String) -> Result<URL, ServiceURLValidationError> {
    let trimmed = InputNormalization.url(raw)
    guard let url = URL(string: trimmed), let scheme = url.scheme, let host = url.host, !host.isEmpty else {
        return .failure(.invalidURL)
    }
    guard scheme.lowercased() == "https" else {
        return .failure(.notHTTPS)
    }
    guard url.user == nil, url.password == nil else {
        return .failure(.containsCredentials)
    }
    // A base URL has no query or fragment (they could also carry a token).
    guard url.query == nil, url.fragment == nil else {
        return .failure(.invalidURL)
    }
    return .success(url)
}
