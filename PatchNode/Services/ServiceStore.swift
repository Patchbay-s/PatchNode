import Foundation
import Observation
import PatchNodeCore

/// Non-secret description of a configured service, safe to hand to background
/// tasks (unlike the SwiftData `ServiceConfig` model).
nonisolated struct ServiceDescriptor: Sendable, Hashable, Identifiable {
    let id: UUID
    let kind: ServiceKind
    let name: String
    let url: URL
}

nonisolated enum ServiceLoadState: Sendable, Hashable {
    case loading
    case loaded
    /// 401, or no token in the Keychain.
    case unauthorized
    /// 403: token valid but missing rights (PVEAuditor).
    case forbidden
    /// Timeout, VPN down, DNS failure…
    case unreachable
    /// 403 HTML page from the reverse proxy (VPN off, Access List): not the token.
    case blockedByProxy
    /// Token accepted but sees nothing (Proxmox Privilege Separation without ACL).
    case insufficientRights
    case failed

    init(error: any Error) {
        switch error {
        case ServiceProviderError.unauthorized: self = .unauthorized
        case ServiceProviderError.forbidden: self = .forbidden
        case ServiceProviderError.unreachable, is TimeoutError: self = .unreachable
        case ServiceProviderError.blockedByProxy: self = .blockedByProxy
        case ServiceProviderError.insufficientRights: self = .insufficientRights
        default: self = .failed
        }
    }

    /// The service must not be asked again for a while: repeated refused requests
    /// can get the user's IP banned (CrowdSec, fail2ban).
    var pausesRequests: Bool {
        pauseReason != nil
    }

    /// Token refusals wait for a pull to refresh; the proxy's resume on their own.
    var pauseReason: PauseReason? {
        switch self {
        case .unauthorized, .forbidden: .tokenRejected
        case .blockedByProxy: .proxyBlocked
        default: nil
        }
    }

    var isFailure: Bool {
        switch self {
        case .loading, .loaded: false
        case .unauthorized, .forbidden, .unreachable, .blockedByProxy, .insufficientRights, .failed: true
        }
    }
}

private nonisolated enum FetchOutcome<Snapshot: Sendable>: Sendable {
    case success(Snapshot)
    case failure(ServiceLoadState, PauseReason?)
}

/// Loads every configured service of one family (Proxmox, Docker…) in parallel and
/// exposes the merged inventory to the Dashboard and the family's tab.
///
/// Shared behaviour: per-service timeout, one URLSession per service (no HTTP/2
/// connection shared between hosts of one reverse proxy), tokens cached in memory
/// only while in the foreground. A refused service is paused (repeated refusals
/// can get the user's IP banned by CrowdSec / fail2ban): until a pull to refresh
/// for its token, 30 s / 60 s / 2 min for the reverse proxy (also lifted by a pull
/// to refresh or a network change). Only the family's primary endpoint decides
/// the service's state; detail screens report nothing here.
@Observable
@MainActor
final class ServiceStore<Snapshot: Sendable, Inventory> {
    typealias Fetch = @Sendable (ServiceDescriptor, _ token: String, HTTPClient) async throws -> Snapshot

    /// Upper bound for one service's refresh.
    let perServiceTimeout: Double

    private(set) var services: [ServiceDescriptor] = []
    private(set) var inventory: Inventory
    private(set) var states: [UUID: ServiceLoadState] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    private var snapshots: [UUID: Snapshot] = [:]
    private(set) var pauses = ServicePauses()
    /// Refresh scheduled for the next automatic resume.
    private var resumeTask: Task<Void, Never>?
    /// Last time a network change lifted proxy pauses: a flapping network must
    /// not bypass the backoff.
    private var lastNetworkResume: Date?
    /// Tokens read from the Keychain, kept only while the app is in the foreground.
    private var tokens: [UUID: String] = [:]
    private var refreshTask: Task<Void, Never>?
    /// Bumped whenever cached tokens are dropped, so a Keychain read that was in
    /// flight at that moment can't put a token back into memory.
    private var secretsGeneration = 0
    /// False between `enterBackground()` and `enterForeground()`: no token may be
    /// cached then, whatever task is still running.
    private var isForeground = true
    private let secretStore: any SecretStore
    let sessions: HTTPSessionPool
    private let log: RequestLog
    private let fetch: Fetch
    private let makeInventory: ([Snapshot]) -> Inventory
    private let levelOf: (Inventory, _ failedServices: Int, _ totalServices: Int) -> HealthLevel
    /// Extra cleanup when the app goes to the background (e.g. dropping OAuth
    /// access tokens held by an `AccessTokenCache`).
    private let onEnterBackground: (@Sendable () async -> Void)?
    /// What changed between a service's last two successful reads that is
    /// worth a line in Diagnostics (e.g. Proxmox guests no longer listed).
    private let compare: ((_ previous: Snapshot, _ current: Snapshot) -> RequestLog.Event?)?

    init(
        secretStore: any SecretStore,
        sessions: HTTPSessionPool = .shared,
        log: RequestLog = .shared,
        perServiceTimeout: Double = 25,
        fetch: @escaping Fetch,
        makeInventory: @escaping ([Snapshot]) -> Inventory,
        level: @escaping (Inventory, Int, Int) -> HealthLevel,
        onEnterBackground: (@Sendable () async -> Void)? = nil,
        compare: ((_ previous: Snapshot, _ current: Snapshot) -> RequestLog.Event?)? = nil
    ) {
        self.secretStore = secretStore
        self.sessions = sessions
        self.log = log
        self.perServiceTimeout = perServiceTimeout
        self.fetch = fetch
        self.makeInventory = makeInventory
        self.levelOf = level
        self.onEnterBackground = onEnterBackground
        self.compare = compare
        self.inventory = makeInventory([])
    }

    var hasLoadedOnce: Bool { lastUpdated != nil }

    /// Client of one service: its own session (connection pool), requests logged
    /// under its name in Settings > Diagnostics.
    func httpClient(for service: ServiceDescriptor, maxAttempts: Int = 2) -> HTTPClient {
        sessions.client(for: service.id, name: service.name, baseURL: service.url, maxAttempts: maxAttempts)
    }

    func pause(for serviceID: UUID) -> ServicePauses.Pause? {
        pauses.pause(for: serviceID)
    }

    var failedServiceCount: Int {
        services.count { states[$0.id]?.isFailure ?? false }
    }

    var level: HealthLevel? {
        guard !services.isEmpty, hasLoadedOnce else { return nil }
        return levelOf(inventory, failedServiceCount, services.count)
    }

    /// Per-service health, for the global "private network unreachable" check.
    var healthStatuses: [HealthStatus] {
        services.compactMap { service -> HealthStatus? in
            switch states[service.id] {
            case .loaded: .ok
            case .unreachable: .unreachable(TimeoutError())
            // The proxy only blocks when the private network is off: counts for the VPN banner.
            case .blockedByProxy: .unreachable(ServiceProviderError.blockedByProxy)
            case .insufficientRights: .degraded("")
            case .unauthorized, .forbidden: .unauthorized
            case .failed: .degraded("")
            case .loading, nil: nil
            }
        }
    }

    var connectivity: GlobalConnectivity {
        aggregateConnectivity(from: healthStatuses)
    }

    /// Called whenever the configured services change (added, renamed, deleted).
    func configure(_ descriptors: [ServiceDescriptor]) {
        guard descriptors != services else { return }
        let previous = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        // Keep cached data only for services still configured identically.
        let unchanged = Set(descriptors.filter { previous[$0.id] == $0 }.map(\.id))
        services = descriptors
        sessions.remove(previous.keys.filter { !unchanged.contains($0) })
        snapshots = snapshots.filter { unchanged.contains($0.key) }
        pauses.keep(only: unchanged)
        states = states.filter { unchanged.contains($0.key) }
        tokens = tokens.filter { unchanged.contains($0.key) }
        rebuildInventory()
        if descriptors.isEmpty { lastUpdated = nil }
        // A service added, renamed or pointed elsewhere loads now rather than at
        // the next polling tick. A refresh in flight took the old list (its
        // results for changed services would be dropped): start over.
        if isForeground, descriptors.contains(where: { !unchanged.contains($0.id) }) {
            refreshTask?.cancel()
            refreshTask = nil
            Task { await refresh() }
        }
    }

    /// The service's credential was replaced in Settings (same ID, name and URL,
    /// so `configure` sees no change): the cached token, pause, state and data
    /// obtained with the old one are dropped, and the services are asked again.
    func credentialChanged(for serviceID: UUID) async {
        guard services.contains(where: { $0.id == serviceID }) else { return }
        tokens[serviceID] = nil
        secretsGeneration &+= 1
        sessions.remove([serviceID])
        pauses.keep(only: Set(services.map(\.id)).subtracting([serviceID]))
        states[serviceID] = nil
        snapshots[serviceID] = nil
        rebuildInventory()
        refreshTask?.cancel()
        refreshTask = nil
        await refresh()
    }

    /// Called when the app goes to the background: cancels any refresh in flight
    /// (its results would be stale on return) and drops the in-memory tokens.
    func enterBackground() {
        isForeground = false
        refreshTask?.cancel()
        refreshTask = nil
        resumeTask?.cancel()
        resumeTask = nil
        isRefreshing = false
        tokens.removeAll()
        secretsGeneration &+= 1
        if let onEnterBackground { Task { await onEnterBackground() } }
    }

    /// Drops every secret held in memory (Keychain tokens, access tokens of
    /// `onEnterBackground`) and waits until it's done: the end of a background
    /// refresh, before iOS suspends the app.
    func dropSecrets() async {
        tokens.removeAll()
        secretsGeneration &+= 1
        await onEnterBackground?()
    }

    func enterForeground() {
        isForeground = true
        scheduleResume()
    }

    /// The network path changed (VPN toggled, Wi-Fi ↔ cellular): the sessions were
    /// reset by the caller; proxy pauses end (the proxy may accept the new route)
    /// and the services are asked again at once. Token pauses stay.
    func networkPathChanged() async {
        guard isForeground, !services.isEmpty else { return }
        if lastNetworkResume.map({ Date.now.timeIntervalSince($0) >= 30 }) ?? true {
            let resumed = pauses.resume(reasons: [.proxyBlocked])
            if !resumed.isEmpty { lastNetworkResume = .now }
            for id in resumed {
                log.append(.event(.resumed(.networkChanged)), label: label(for: id))
            }
        }
        // The refresh in flight used the dropped sessions: start over.
        refreshTask?.cancel()
        refreshTask = nil
        await refresh()
    }

    /// Polling entry point: skips the network when the data is younger than
    /// `maxAge` seconds (tab switch, return from a detail screen, Control Center).
    func refresh(ifOlderThan maxAge: Int) async {
        if let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < Double(maxAge) {
            return
        }
        await refresh()
    }

    /// Refreshes every service; concurrent callers share the refresh in flight.
    /// `force` (pull to refresh) replaces a refresh in flight instead of joining it
    /// and resumes paused services.
    func refresh(force: Bool = false) async {
        // Nothing goes out while the app is in the background (e.g. the end of
        // an action's follow-up after the user locked the phone).
        guard isForeground else { return }
        if force {
            refreshTask?.cancel()
            refreshTask = nil
            for id in pauses.resume(reasons: [.tokenRejected, .proxyBlocked]) {
                log.append(.event(.resumed(.pullToRefresh)), label: label(for: id))
            }
        }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        isRefreshing = true
        await task.value
        // A forced refresh may have replaced this one: only the current task ends
        // the "refreshing" state.
        if refreshTask == task {
            refreshTask = nil
            isRefreshing = false
        }
    }

    /// Refresh from a background task (BGAppRefreshTask). Call `enterBackground()`
    /// first (a cold launch in the background never sees a scene phase): tokens
    /// are then read from the Keychain for this refresh only, never cached.
    /// Each service gets `timeout` seconds at most, so the whole refresh fits in
    /// iOS's background budget; expiry cancels the requests in flight. Paused
    /// services stay paused.
    func refreshInBackground(timeout: Double) async {
        if let existing = refreshTask {
            await withTaskCancellationHandler {
                await existing.value
            } onCancel: {
                existing.cancel()
            }
            return
        }
        let task = Task { await performRefresh(timeout: timeout) }
        refreshTask = task
        isRefreshing = true
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            // The background task expired: stop the requests in flight.
            task.cancel()
        }
        if refreshTask == task {
            refreshTask = nil
            isRefreshing = false
        }
    }

    /// Descriptor and token for a detail screen; nil while the token is refused.
    func credentials(for serviceID: UUID) async -> (ServiceDescriptor, String)? {
        guard isForeground, !pauses.isPaused(serviceID, at: .now),
              let service = services.first(where: { $0.id == serviceID })
        else { return nil }
        switch await token(for: serviceID) {
        case .found(let token): return isForeground ? (service, token) : nil
        case .missing where !service.kind.requiresCredential: return (service, "")
        case .missing, .unavailable: return nil
        }
    }

    /// For a single read that may run in the background (SMART at the chosen
    /// time): no foreground requirement, the token is read for this call only
    /// and never kept while in the background (`token(for:)` caches it only in
    /// the foreground). A paused service gets nothing.
    func credentialsForSingleRead(for serviceID: UUID) async -> (ServiceDescriptor, String)? {
        guard !pauses.isPaused(serviceID, at: .now),
              let service = services.first(where: { $0.id == serviceID })
        else { return nil }
        switch await token(for: serviceID) {
        case .found(let token): return (service, token)
        case .missing where !service.kind.requiresCredential: return (service, "")
        case .missing, .unavailable: return nil
        }
    }

    /// A screen other than the refresh got a 401/403 (or a proxy 403) for this
    /// service (Docker, Observability, Home Assistant; Proxmox detail screens
    /// don't report: only its primary endpoint decides).
    func reportRejectedToken(for serviceID: UUID, state: ServiceLoadState) {
        guard let reason = state.pauseReason,
              services.contains(where: { $0.id == serviceID })
        else { return }
        applyPause(serviceID, reason: reason)
        states[serviceID] = state
    }

    private func performRefresh(timeout: Double? = nil) async {
        guard !services.isEmpty else { return }

        let now = Date.now
        var jobs: [(ServiceDescriptor, String)] = []
        for service in services where !pauses.isPaused(service.id, at: now) {
            // Backgrounded meanwhile: stop reading the Keychain.
            guard !Task.isCancelled else { return }
            let lookup = await token(for: service.id)
            // Cancelled while reading (credential replaced, network change): the
            // newer refresh owns the state now.
            guard !Task.isCancelled else { return }
            guard services.contains(service) else { continue }
            switch lookup {
            case .found(let token):
                if states[service.id] == nil { states[service.id] = .loading }
                jobs.append((service, token))
            case .missing where !service.kind.requiresCredential:
                // Optional credential (public status page, Prometheus without auth).
                if states[service.id] == nil { states[service.id] = .loading }
                jobs.append((service, ""))
            case .missing:
                states[service.id] = .unauthorized
                snapshots[service.id] = nil
                // Ends an expired automatic pause: nothing to probe, no resume loop.
                pauses.recordFailure(service.id, reason: nil, at: now)
            case .unavailable:
                // Keychain temporarily unreadable: not a refused token, keep the data.
                states[service.id] = .failed
                pauses.recordFailure(service.id, reason: nil, at: now)
            }
        }

        guard !Task.isCancelled else { return }
        let timeout = timeout ?? perServiceTimeout
        let fetch = fetch
        let outcomes = await withTaskGroup(of: (UUID, FetchOutcome<Snapshot>).self) { group in
            for (service, token) in jobs {
                let httpClient = httpClient(for: service)
                // Tags the log: first request after an automatic pause.
                let context: RequestLog.Context = pauses.isResumeProbe(service.id, at: now)
                    ? .resumeProbe(attempt: pauses.pause(for: service.id)?.strikes ?? 1)
                    : .normal
                group.addTask {
                    do {
                        let snapshot = try await RequestLog.$context.withValue(context) {
                            try await withTimeout(seconds: timeout) {
                                try await fetch(service, token, httpClient)
                            }
                        }
                        return (service.id, .success(snapshot))
                    } catch {
                        return (service.id, .failure(ServiceLoadState(error: error), PauseReason(error: error)))
                    }
                }
            }
            var outcomes: [(UUID, FetchOutcome<Snapshot>)] = []
            for await outcome in group { outcomes.append(outcome) }
            return outcomes
        }

        // Cancelled (app backgrounded or pull to refresh): results are discarded.
        guard !Task.isCancelled else { return }
        let jobDescriptors = Dictionary(uniqueKeysWithValues: jobs.map { ($0.0.id, $0.0) })
        let current = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
        // A service paused meanwhile (token refused on a detail screen) keeps its state.
        for (id, outcome) in outcomes where current[id] != nil && current[id] == jobDescriptors[id]
            && !pauses.isPaused(id, at: .now) {
            switch outcome {
            case .success(let snapshot):
                if let previous = snapshots[id], let event = compare?(previous, snapshot) {
                    log.append(.event(event), label: label(for: id))
                }
                snapshots[id] = snapshot
                states[id] = .loaded
                if pauses.recordSuccess(id) {
                    log.append(.event(.resumed(.succeeded)), label: label(for: id))
                }
            case .failure(let state, let reason):
                snapshots[id] = nil
                states[id] = state
                if let reason {
                    applyPause(id, reason: reason)
                } else {
                    // Timeout, 5xx, 421…: asked again at the next refresh.
                    pauses.recordFailure(id, reason: nil, at: .now)
                }
            }
        }
        rebuildInventory()
        lastUpdated = .now
        scheduleResume()
    }

    private func applyPause(_ id: UUID, reason: PauseReason) {
        let now = Date.now
        guard let pause = pauses.recordFailure(id, reason: reason, at: now) else { return }
        tokens[id] = nil
        log.append(
            .event(.paused(reason: reason, resumeAfter: pause.resumeAt?.timeIntervalSince(now))),
            label: label(for: id)
        )
        scheduleResume()
    }

    /// Refreshes when the next automatic pause ends, while in the foreground.
    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = nil
        guard isForeground, let next = pauses.nextResume else { return }
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0) + 0.5))
            guard !Task.isCancelled, let self else { return }
            self.resumeTask = nil
            await self.refresh()
        }
    }

    private func label(for id: UUID) -> RequestLog.Label {
        RequestLog.Label(serviceID: id, serviceName: services.first { $0.id == id }?.name ?? "?")
    }

    private enum TokenLookup {
        case found(String)
        case missing
        case unavailable
    }

    private func token(for id: UUID) async -> TokenLookup {
        if let token = tokens[id] { return .found(token) }
        // Demo service: its fake credential, never the Keychain.
        if let service = services.first(where: { $0.id == id }),
           let credential = DemoMode.credential(for: id, url: service.url) {
            return .found(credential)
        }
        // Only the token saved for this server: an address changed by iCloud
        // sync or an import never receives it.
        guard let service = services.first(where: { $0.id == id }), let origin = CredentialOrigin.of(service.url) else {
            return .missing
        }
        let generation = secretsGeneration
        let stored: String?
        do {
            stored = try await secretStore.read(for: id, origin: origin)
        } catch {
            return .unavailable
        }
        guard let token = stored, !token.isEmpty else { return .missing }
        if generation == secretsGeneration, isForeground, !Task.isCancelled,
           services.contains(where: { $0.id == id }) {
            tokens[id] = token
        }
        return .found(token)
    }

    private func rebuildInventory() {
        // Service order decides which service "owns" data seen twice.
        inventory = makeInventory(services.compactMap { snapshots[$0.id] })
    }
}

/// What the root view and the dashboard need from every store, whatever its
/// service family: lifecycle, refresh and health.
@MainActor
protocol ManagedStore: AnyObject, Sendable {
    var services: [ServiceDescriptor] { get }
    var states: [UUID: ServiceLoadState] { get }
    func pause(for serviceID: UUID) -> ServicePauses.Pause?
    var lastUpdated: Date? { get }
    var healthStatuses: [HealthStatus] { get }
    func configure(_ descriptors: [ServiceDescriptor])
    func enterForeground()
    func enterBackground()
    func refresh(force: Bool) async
    func refresh(ifOlderThan maxAge: Int) async
    func refreshInBackground(timeout: Double) async
    func dropSecrets() async
    func networkPathChanged() async
    func credentialChanged(for serviceID: UUID) async
}

extension ServiceStore: ManagedStore {}
