import Foundation

public protocol ServiceProvider: Sendable {
    var id: UUID { get }
    var kind: ServiceKind { get }
    var displayName: String { get }

    /// Vérifie la connexion et les droits du jeton.
    func healthCheck() async throws -> HealthStatus

    /// Résumé affiché sur le tableau de bord.
    func summary() async throws -> ServiceSummary
}
