import Foundation
import PatchNodeCore

public enum TailscaleProviderError: Error, Sendable, Equatable {
    case unreachable
}

/// What the Tailscale API returned during a refresh.
public struct TailscaleServiceSnapshot: Sendable, Hashable {
    public let serviceID: UUID
    public let serviceName: String
    public let devices: [TailscaleDevice]
    public let fetchedAt: Date

    public init(serviceID: UUID, serviceName: String, devices: [TailscaleDevice], fetchedAt: Date = .now) {
        self.serviceID = serviceID; self.serviceName = serviceName; self.devices = devices; self.fetchedAt = fetchedAt
    }
}

/// Devices of every configured tailnet, with their issues.
public struct TailscaleInventory: Sendable {
    public struct Item: Sendable, Hashable, Identifiable {
        public let serviceID: UUID
        public let serviceName: String
        public let device: TailscaleDevice
        public let isOnline: Bool
        public let issues: [TailscaleDeviceIssue]
        public var id: String { "\(serviceID.uuidString)|\(device.id)" }
    }

    public static let offlineAlertAge: TimeInterval = 24 * 60 * 60
    public static let keyExpiryWarning: TimeInterval = 14 * 24 * 60 * 60

    /// Devices with issues first, then online ones, then by name.
    public let devices: [Item]
    public let overview: TailscaleOverview

    public init(snapshots: [TailscaleServiceSnapshot], now: Date = .now) {
        var items: [Item] = []
        for snapshot in snapshots {
            for device in snapshot.devices {
                let online = device.isOnline(now: now)
                items.append(Item(
                    serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, device: device,
                    isOnline: online, issues: Self.issues(of: device, isOnline: online, now: now)
                ))
            }
        }
        devices = items.sorted { lhs, rhs in
            if lhs.issues.isEmpty != rhs.issues.isEmpty { return !lhs.issues.isEmpty }
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return lhs.device.shortName.localizedStandardCompare(rhs.device.shortName) == .orderedAscending
        }
        overview = TailscaleOverview(items: devices)
    }

    static func issues(of device: TailscaleDevice, isOnline: Bool, now: Date) -> [TailscaleDeviceIssue] {
        var issues: [TailscaleDeviceIssue] = []
        if !device.authorized { issues.append(.notAuthorized) }
        if !isOnline, let lastSeen = device.lastSeen, now.timeIntervalSince(lastSeen) > offlineAlertAge {
            issues.append(.offline(since: lastSeen))
        }
        if let expiry = device.keyExpiry {
            if expiry <= now {
                issues.append(.keyExpired(expiry))
            } else if expiry.timeIntervalSince(now) < keyExpiryWarning {
                issues.append(.keyExpiringSoon(expiry))
            }
        }
        return issues
    }
}

public struct TailscaleOverview: Sendable, Hashable {
    public let total: Int
    public let online: Int
    public let offlineOver24h: Int
    public let keysExpiringSoon: Int
    public let keysExpired: Int
    public let awaitingApproval: Int

    init(items: [TailscaleInventory.Item]) {
        total = items.count
        online = items.count(where: \.isOnline)
        offlineOver24h = items.count { $0.issues.contains { if case .offline = $0 { true } else { false } } }
        keysExpiringSoon = items.count { $0.issues.contains { if case .keyExpiringSoon = $0 { true } else { false } } }
        keysExpired = items.count { $0.issues.contains { if case .keyExpired = $0 { true } else { false } } }
        awaitingApproval = items.count { $0.issues.contains(.notAuthorized) }
    }

    /// Critical: the API didn't answer or a key has expired. Warning: a device
    /// offline for more than 24 h, a key expiring within 14 days or a device
    /// waiting for approval.
    public func level(failedServices: Int, totalServices: Int) -> HealthLevel {
        if totalServices > 0 && failedServices >= totalServices { return .critical }
        if keysExpired > 0 { return .critical }
        if failedServices > 0 || offlineOver24h > 0 || keysExpiringSoon > 0 || awaitingApproval > 0 { return .warning }
        return .ok
    }
}

/// Tailscale through its public API (OAuth client or API access token).
public struct TailscaleProvider: ServiceProvider {
    public let id: UUID
    public let kind: ServiceKind = .tailscale
    public let displayName: String
    public let client: TailscaleClient

    public init(
        id: UUID, displayName: String, baseURL: URL = TailscaleClient.defaultBaseURL, credential: String,
        tokenCache: AccessTokenCache = AccessTokenCache(), httpClient: any HTTPClientProtocol = HTTPClient()
    ) {
        self.id = id
        self.displayName = displayName
        client = TailscaleClient(baseURL: baseURL, serviceID: id, credential: credential, tokenCache: tokenCache, httpClient: httpClient)
    }

    public func healthCheck() async throws -> HealthStatus {
        do {
            try await client.checkConnection()
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
            return .unreachable(TailscaleProviderError.unreachable)
        }
    }

    public func summary() async throws -> ServiceSummary {
        let devices = try await client.devices()
        let overview = TailscaleInventory(snapshots: [TailscaleServiceSnapshot(serviceID: id, serviceName: displayName, devices: devices)]).overview
        return ServiceSummary(
            headline: "\(overview.online)/\(overview.total)",
            details: [
                "online": String(overview.online),
                "total": String(overview.total),
                "offlineOver24h": String(overview.offlineOver24h),
                "keysExpiringSoon": String(overview.keysExpiringSoon),
            ]
        )
    }
}
