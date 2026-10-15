import Foundation
import PatchNodeCore

public enum ObservabilityProviderError: Error, Sendable, Equatable {
    case unreachable
    /// The Uptime Kuma URL isn't a status page URL (…/status/<slug>).
    case notAStatusPage
    case unsupportedKind
}

/// Prometheus, Alertmanager, Grafana or an Uptime Kuma status page.
public struct ObservabilityProvider: ServiceProvider {
    public static let supportedKinds: [ServiceKind] = [.prometheus, .alertmanager, .grafana, .uptimeKuma]

    public let id: UUID
    public let kind: ServiceKind
    public let displayName: String
    private let baseURL: URL
    private let credential: String
    private let httpClient: any HTTPClientProtocol

    /// `credential`: optional `user:password` (Prometheus, Alertmanager), service
    /// account token (Grafana), ignored for Uptime Kuma.
    public init(id: UUID, kind: ServiceKind, displayName: String, baseURL: URL, credential: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.id = id; self.kind = kind; self.displayName = displayName
        self.baseURL = baseURL; self.credential = credential; self.httpClient = httpClient
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            switch kind {
            case .prometheus:
                try await PrometheusClient(baseURL: baseURL, credential: credential, httpClient: httpClient).checkConnection()
            case .alertmanager:
                try await AlertmanagerClient(baseURL: baseURL, credential: credential, httpClient: httpClient).checkConnection()
            case .grafana:
                try await GrafanaClient(baseURL: baseURL, token: credential, httpClient: httpClient).checkConnection()
            case .uptimeKuma:
                guard let location = UptimeKumaLocation(statusPageURL: baseURL) else {
                    return .degraded("not a status page URL")
                }
                try await UptimeKumaClient(location: location, httpClient: httpClient).checkConnection()
            default:
                return .degraded("unsupported service")
            }
            return .ok
        } catch ServiceProviderError.blockedByProxy {
            // The reverse proxy refused (VPN off?): not a token problem.
            return .unreachable(ServiceProviderError.blockedByProxy)
        } catch ServiceProviderError.unauthorized, ServiceProviderError.forbidden {
            return .unauthorized
        } catch ServiceProviderError.unexpectedStatus(let code) {
            return .degraded("HTTP \(code)")
        } catch ServiceProviderError.invalidResponse, ServiceProviderError.decodingFailed {
            return .degraded("invalid response")
        } catch let error as CancellationError {
            throw error
        } catch {
            return .unreachable(ObservabilityProviderError.unreachable)
        }
    }

    /// Active alerts (critical/warning) and Prometheus targets down.
    public func summary() async throws -> ServiceSummary {
        let snapshot = try await Self.loadSnapshot(
            kind: kind, baseURL: baseURL, credential: credential,
            serviceID: id, serviceName: displayName, httpClient: httpClient
        )
        let overview = ObservabilityInventory(snapshots: [snapshot]).overview
        return ServiceSummary(
            headline: String(overview.activeAlerts),
            details: [
                "activeAlerts": String(overview.activeAlerts),
                "critical": String(overview.critical),
                "warning": String(overview.warning),
                "targetsDown": String(overview.targetsDown),
            ]
        )
    }

    public static func loadSnapshot(
        kind: ServiceKind, baseURL: URL, credential: String,
        serviceID: UUID, serviceName: String, httpClient: any HTTPClientProtocol
    ) async throws -> ObservabilityServiceSnapshot {
        switch kind {
        case .prometheus:
            let targets = try await PrometheusClient(baseURL: baseURL, credential: credential, httpClient: httpClient).targets()
            return ObservabilityServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, baseURL: baseURL, targets: targets)
        case .alertmanager:
            let alerts = try await AlertmanagerClient(baseURL: baseURL, credential: credential, httpClient: httpClient).alerts()
            return ObservabilityServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, baseURL: baseURL, alerts: alerts)
        case .grafana:
            let client = GrafanaClient(baseURL: baseURL, token: credential, httpClient: httpClient)
            // Dashboards validate the token; alerts are optional (unified alerting off).
            // Sequential: a refused token costs one request (dashboards), not two.
            let dashboards = try await client.dashboards()
            let alerts: [ObservabilityAlert]
            do {
                alerts = try await client.alerts()
            } catch let error as CancellationError {
                throw error
            } catch {
                alerts = []
            }
            return ObservabilityServiceSnapshot(
                serviceID: serviceID, serviceName: serviceName, kind: kind, baseURL: baseURL,
                alerts: alerts, dashboards: dashboards
            )
        case .uptimeKuma:
            guard let location = UptimeKumaLocation(statusPageURL: baseURL) else {
                throw ObservabilityProviderError.notAStatusPage
            }
            let page = try await UptimeKumaClient(location: location, httpClient: httpClient).page()
            return ObservabilityServiceSnapshot(
                serviceID: serviceID, serviceName: serviceName, kind: kind, baseURL: location.baseURL, statusPage: page
            )
        default:
            throw ObservabilityProviderError.unsupportedKind
        }
    }
}
