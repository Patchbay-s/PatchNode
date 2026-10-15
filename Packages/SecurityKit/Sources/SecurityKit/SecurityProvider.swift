import Foundation
import PatchNodeCore

public enum SecurityProviderError: Error, Sendable, Equatable {
    case unreachable
    case unsupportedKind
}

/// What one security service returned during a refresh.
public struct SecurityServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let kind: ServiceKind
    public let decisions: [CrowdSecDecision]
    public let proxyHosts: [NPMProxyHost]
    public let adGuard: AdGuardSummary?
    public let fetchedAt: Date

    public init(
        serviceID: UUID, serviceName: String, kind: ServiceKind,
        decisions: [CrowdSecDecision] = [], proxyHosts: [NPMProxyHost] = [], adGuard: AdGuardSummary? = nil,
        fetchedAt: Date = .now
    ) {
        self.serviceID = serviceID; self.serviceName = serviceName; self.kind = kind
        self.decisions = decisions; self.proxyHosts = proxyHosts; self.adGuard = adGuard; self.fetchedAt = fetchedAt
    }
}

/// CrowdSec bans, NPM hosts and AdGuard statistics across the configured services.
public struct SecurityInventory: Sendable {
    public struct DecisionItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let decision: CrowdSecDecision
        public var id: String { "\(serviceID.uuidString)|\(decision.id)" }
    }

    public struct HostItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let host: NPMProxyHost
        public var id: String { "\(serviceID.uuidString)|\(host.id)" }
    }

    public struct AdGuardItem: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let summary: AdGuardSummary
        public var id: String { serviceID.uuidString }
    }

    /// Soonest expiry last: the most recent bans (longest remaining) first.
    public let decisions: [DecisionItem]
    /// Failing hosts first, then by domain.
    public let hosts: [HostItem]
    public let adGuards: [AdGuardItem]
    public let overview: SecurityOverview

    public init(snapshots: [SecurityServiceSnapshot]) {
        var decisions: [DecisionItem] = []
        var hosts: [HostItem] = []
        var adGuards: [AdGuardItem] = []
        for snapshot in snapshots {
            decisions += snapshot.decisions.map { DecisionItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, decision: $0) }
            hosts += snapshot.proxyHosts.map { HostItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, host: $0) }
            if let summary = snapshot.adGuard {
                adGuards.append(AdGuardItem(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, summary: summary))
            }
        }
        self.decisions = decisions.sorted { ($0.decision.expiresAt ?? .distantFuture) > ($1.decision.expiresAt ?? .distantFuture) }
        self.hosts = hosts.sorted { lhs, rhs in
            if lhs.host.isFailing != rhs.host.isFailing { return lhs.host.isFailing }
            return lhs.host.title.localizedStandardCompare(rhs.host.title) == .orderedAscending
        }
        self.adGuards = adGuards
        overview = SecurityOverview(decisions: self.decisions, hosts: self.hosts, adGuards: adGuards)
    }

    public func decisions(for serviceID: UUID) -> [DecisionItem] { decisions.filter { $0.serviceID == serviceID } }
    public func hosts(for serviceID: UUID) -> [HostItem] { hosts.filter { $0.serviceID == serviceID } }
}

public struct SecurityOverview: Sendable, Hashable {
    public let activeBans: Int
    public let hostsTotal: Int
    public let hostsEnabled: Int
    public let hostsFailing: Int
    public let dnsQueries: Int
    public let dnsBlocked: Int
    public let protectionDisabled: Int

    init(decisions: [SecurityInventory.DecisionItem], hosts: [SecurityInventory.HostItem], adGuards: [SecurityInventory.AdGuardItem]) {
        activeBans = decisions.count { !$0.decision.simulated }
        hostsTotal = hosts.count
        hostsEnabled = hosts.count { $0.host.enabled }
        hostsFailing = hosts.count { $0.host.isFailing }
        dnsQueries = adGuards.reduce(0) { $0 + $1.summary.dnsQueries }
        dnsBlocked = adGuards.reduce(0) { $0 + $1.summary.blocked }
        protectionDisabled = adGuards.count { !$0.summary.protectionEnabled }
    }

    /// Bans are CrowdSec doing its job: informational, not a warning.
    /// Warning: a service failed, an NPM host is refused by nginx or AdGuard
    /// protection is off. Critical: no service answered.
    public func level(failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if failedServices > 0 || hostsFailing > 0 || protectionDisabled > 0 { return .warning }
        return .ok
    }
}

/// CrowdSec, Nginx Proxy Manager or AdGuard Home.
public struct SecurityProvider: ServiceProvider {
    public static let supportedKinds: [ServiceKind] = [.crowdSec, .nginxProxyManager, .adGuardHome]

    public let id: UUID
    public let kind: ServiceKind
    public let displayName: String
    private let baseURL: URL
    private let credential: String
    private let tokenCache: AccessTokenCache
    private let httpClient: any HTTPClientProtocol

    /// `credential`: bouncer key (CrowdSec), `email:password` (NPM), `user:password` (AdGuard).
    public init(
        id: UUID, kind: ServiceKind, displayName: String, baseURL: URL, credential: String,
        tokenCache: AccessTokenCache = AccessTokenCache(), httpClient: any HTTPClientProtocol = HTTPClient()
    ) {
        self.id = id; self.kind = kind; self.displayName = displayName
        self.baseURL = baseURL; self.credential = credential
        self.tokenCache = tokenCache; self.httpClient = httpClient
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            _ = try await Self.loadSnapshot(
                kind: kind, baseURL: baseURL, credential: credential, serviceID: id, serviceName: displayName,
                tokenCache: tokenCache, httpClient: httpClient
            )
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
        } catch SecurityProviderError.unsupportedKind {
            return .degraded("unsupported service")
        } catch let error as CancellationError {
            throw error
        } catch {
            return .unreachable(SecurityProviderError.unreachable)
        }
    }

    public func summary() async throws -> ServiceSummary {
        let snapshot = try await Self.loadSnapshot(
            kind: kind, baseURL: baseURL, credential: credential, serviceID: id, serviceName: displayName,
            tokenCache: tokenCache, httpClient: httpClient
        )
        let overview = SecurityInventory(snapshots: [snapshot]).overview
        return ServiceSummary(
            headline: String(overview.activeBans),
            details: [
                "activeBans": String(overview.activeBans),
                "hostsTotal": String(overview.hostsTotal),
                "hostsFailing": String(overview.hostsFailing),
                "dnsQueries": String(overview.dnsQueries),
                "dnsBlocked": String(overview.dnsBlocked),
            ]
        )
    }

    public static func loadSnapshot(
        kind: ServiceKind, baseURL: URL, credential: String, serviceID: UUID, serviceName: String,
        tokenCache: AccessTokenCache, httpClient: any HTTPClientProtocol
    ) async throws -> SecurityServiceSnapshot {
        switch kind {
        case .crowdSec:
            let decisions = try await CrowdSecClient(baseURL: baseURL, apiKey: credential, httpClient: httpClient).decisions()
            return SecurityServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, decisions: decisions)
        case .nginxProxyManager:
            let hosts = try await NPMClient(
                baseURL: baseURL, serviceID: serviceID, credential: credential, tokenCache: tokenCache, httpClient: httpClient
            ).proxyHosts()
            return SecurityServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, proxyHosts: hosts)
        case .adGuardHome:
            let summary = try await AdGuardClient(baseURL: baseURL, credential: credential, httpClient: httpClient).summary()
            return SecurityServiceSnapshot(serviceID: serviceID, serviceName: serviceName, kind: kind, adGuard: summary)
        default:
            throw SecurityProviderError.unsupportedKind
        }
    }
}
