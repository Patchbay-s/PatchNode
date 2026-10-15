public struct ServiceSummary: Sendable {
    public let headline: String
    public let details: [String: String]

    public init(headline: String, details: [String: String] = [:]) {
        self.headline = headline
        self.details = details
    }
}
