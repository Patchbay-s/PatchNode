import Foundation
import PatchNodeCore

public enum HomeServicesProviderError: Error, Sendable, Equatable {
    case unreachable
    case unsupportedKind
}

/// What one Home Assistant or Glances service returned during a refresh.
public struct HomeServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let kind: ServiceKind
    /// Every entity, sorted by name (for the entity picker).
    public let entities: [HAEntity]
    /// Entities by ID, built with the snapshot (off the main actor).
    public let entitiesByID: [String: HAEntity]
    public let glances: GlancesSummary?
    public let fetchedAt: Date

    public init(serviceID: UUID, serviceName: String, kind: ServiceKind, entities: [HAEntity] = [], glances: GlancesSummary? = nil, fetchedAt: Date = .now) {
        self.serviceID = serviceID; self.serviceName = serviceName; self.kind = kind
        self.entities = entities; self.glances = glances; self.fetchedAt = fetchedAt
        entitiesByID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

public struct HomeServicesInventory: Sendable {
    public struct HomeAssistantItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let entities: [HAEntity]
        let entitiesByID: [String: HAEntity]
        public var id: UUID { serviceID }

        /// Entity by ID, for the pinned entities.
        public func entity(_ entityID: String) -> HAEntity? {
            entitiesByID[entityID]
        }
    }

    public struct GlancesItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let summary: GlancesSummary
        public var id: UUID { serviceID }
    }

    public let homeAssistants: [HomeAssistantItem]
    public let glances: [GlancesItem]
    public let glancesOverview: GlancesOverview

    public init(snapshots: [HomeServiceSnapshot]) {
        var homeAssistants: [HomeAssistantItem] = []
        var glances: [GlancesItem] = []
        for snapshot in snapshots {
            switch snapshot.kind {
            case .homeAssistant:
                homeAssistants.append(HomeAssistantItem(
                    serviceID: snapshot.serviceID, serviceName: snapshot.serviceName,
                    entities: snapshot.entities, entitiesByID: snapshot.entitiesByID
                ))
            case .glances:
                if let summary = snapshot.glances {
                    glances.append(GlancesItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, summary: summary))
                }
            default:
                break
            }
        }
        self.homeAssistants = homeAssistants
        self.glances = glances
        glancesOverview = GlancesOverview(items: glances)
    }

    public func homeAssistant(_ serviceID: UUID) -> HomeAssistantItem? {
        homeAssistants.first { $0.serviceID == serviceID }
    }
}

public struct GlancesOverview: Sendable, Hashable {
    public let hosts: Int
    public let fullFileSystems: Int
    public let memoryPressure: Int

    init(items: [HomeServicesInventory.GlancesItem]) {
        hosts = items.count
        fullFileSystems = items.reduce(0) { $0 + $1.summary.fullFileSystems.count }
        memoryPressure = items.count { ($0.summary.memoryPercent ?? 0) >= GlancesSummary.memoryAlertPercent }
    }
}

extension HomeServicesInventory {
    /// Critical: no service answered. Warning: a service failed, a Glances file
    /// system is above 85 % or memory above 90 %.
    public func level(kind: ServiceKind, failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if failedServices > 0 { return .warning }
        if kind == .glances, glancesOverview.fullFileSystems > 0 || glancesOverview.memoryPressure > 0 { return .warning }
        return .ok
    }
}

/// Home Assistant or Glances.
public struct HomeServicesProvider: ServiceProvider {
    public static let supportedKinds: [ServiceKind] = [.homeAssistant, .glances]

    public let id: UUID
    public let kind: ServiceKind
    public let displayName: String
    private let baseURL: URL
    private let credential: String
    private let httpClient: any HTTPClientProtocol

    /// `credential`: long-lived token (Home Assistant), optional `user:password` (Glances).
    public init(id: UUID, kind: ServiceKind, displayName: String, baseURL: URL, credential: String, httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.id = id; self.kind = kind; self.displayName = displayName
        self.baseURL = baseURL; self.credential = credential; self.httpClient = httpClient
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            switch kind {
            case .homeAssistant:
                try await HomeAssistantClient(baseURL: baseURL, token: credential, httpClient: httpClient).checkConnection()
            case .glances:
                try await GlancesClient(baseURL: baseURL, credential: credential, httpClient: httpClient).checkConnection()
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
            return .unreachable(HomeServicesProviderError.unreachable)
        }
    }

    public func summary() async throws -> ServiceSummary {
        let snapshot = try await Self.loadSnapshot(
            kind: kind, baseURL: baseURL, credential: credential, serviceID: id, serviceName: displayName, httpClient: httpClient
        )
        if let glances = snapshot.glances {
            return ServiceSummary(
                headline: glances.cpuPercent.map { String(Int($0.rounded())) } ?? "–",
                details: ["fullFileSystems": String(glances.fullFileSystems.count)]
            )
        }
        return ServiceSummary(headline: String(snapshot.entities.count), details: ["entities": String(snapshot.entities.count)])
    }

    public static func loadSnapshot(
        kind: ServiceKind, baseURL: URL, credential: String, serviceID: UUID, serviceName: String, httpClient: any HTTPClientProtocol
    ) async throws -> HomeServiceSnapshot {
        switch kind {
        case .homeAssistant:
            let entities = try await HomeAssistantClient(baseURL: baseURL, token: credential, httpClient: httpClient).states()
            let sorted = entities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return HomeServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, entities: sorted)
        case .glances:
            let summary = try await GlancesClient(baseURL: baseURL, credential: credential, httpClient: httpClient).summary()
            return HomeServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, glances: summary)
        default:
            throw HomeServicesProviderError.unsupportedKind
        }
    }
}
