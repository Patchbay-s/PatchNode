import Foundation
import Observation
import SwiftData
import UIKit
import BackgroundTasks
import WidgetKit
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

/// The SwiftData container, shared by the app's scene, the background refresh and
/// the App Intents (same schema, same store). Opened once per launch.
///
/// `groupContainer: .none`: with the App Group enabled, SwiftData would otherwise
/// move its store (service URLs) into the container the widget extension reads,
/// and start from an empty store — orphaning the tokens in the Keychain.
/// `cloudKitDatabase`: `.automatic` (the iCloud container of the entitlements,
/// the user's private database) only if the user turned on iCloud sync, `.none`
/// otherwise. Read at launch: the option applies at the next one.
/// No name or URL: the default store, the one 1.0 created. The versioned schema
/// and its migration plan (`PatchNodeModelStore`) open it without losing anything.
///
/// If the store can't open (a failed migration…), the app shows
/// `StoreErrorView` instead of crashing, and never deletes the store: the next
/// version can still open it.
enum AppModelContainer {
    enum State {
        case ready(ModelContainer)
        case failed(code: String)
    }

    /// How iCloud sync came out at launch.
    enum SyncStatus: Equatable {
        case off
        case on
        /// Asked for, but the CloudKit store couldn't open: local store instead.
        case unavailable
    }

    /// Opened on first use (main actor: the app target's default isolation).
    private static let launch: (state: State, sync: SyncStatus) = {
        var sync = SyncStatus.off
        if CloudSyncSettings.isEnabled() {
            if let container = try? open(cloudKit: .automatic) {
                return (.ready(container), .on)
            }
            sync = .unavailable
        }
        do {
            return (.ready(try open(cloudKit: .none)), sync)
        } catch {
            // Domain and code only: a store error's description holds file paths.
            let error = error as NSError
            return (.failed(code: "\(error.domain) \(error.code)"), sync)
        }
    }()

    static var state: State { launch.state }
    static var syncStatus: SyncStatus { launch.sync }

    /// nil when the store couldn't open (the error screen is shown).
    static var shared: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    /// Empty, in memory: lets the demo run from the error screen without
    /// touching the store that failed.
    static let demoFallback: ModelContainer? = try? ModelContainer(
        for: PatchNodeModelStore.schema,
        configurations: [ModelConfiguration(schema: PatchNodeModelStore.schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)]
    )

    /// Binds the tokens saved by 1.0 (no server attached) to their service's
    /// address, once, while the configuration is still local: iCloud is off by
    /// default, so the first 1.1 launch always gets here before any synced
    /// address can arrive. Until done, an unbound token is used as in 1.0.
    static func bindCredentialsIfNeeded() async {
        guard !CredentialBinding.isDone(), let container = shared else { return }
        // Sync turned on before binding (an earlier failed attempt): the stored
        // addresses may come from another device. Never bind to them; those
        // tokens are entered again.
        guard syncStatus == .off, !CloudSyncSettings.isEnabled() else {
            CredentialBinding.markDone()
            return
        }
        let configs = (try? ModelContext(container).fetch(FetchDescriptor<ServiceConfig>())) ?? []
        var origins: [UUID: String] = [:]
        for config in configs where origins[config.id] == nil {
            origins[config.id] = CredentialOrigin.of(config.urlString)
        }
        do {
            try await KeychainSecretStore().bindUnlabeled(origins: origins)
            CredentialBinding.markDone()
        } catch {
            // Tried again at the next launch.
        }
    }

    private static func open(cloudKit: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PatchNodeModelStore.schema, groupContainer: .none, cloudKitDatabase: cloudKit)
        return try PatchNodeModelStore.makeContainer(configuration: configuration)
    }
}

/// Every store of the app, plus what ties them to iOS: the snapshot shared with
/// the widgets and the background refresh.
@Observable
@MainActor
final class AppModel {
    let lockController = AppLockController()
    let actionLog = ActionLog()
    let proxmoxStore = ProxmoxStore.proxmox(secretStore: KeychainSecretStore())
    let dockerStore = DockerStore.docker(secretStore: KeychainSecretStore())
    let observabilityStore = ObservabilityStore.observability(secretStore: KeychainSecretStore())
    let backupStore = BackupStore.backups(secretStore: KeychainSecretStore())
    let tailscaleStore = TailscaleStore.tailscale(secretStore: KeychainSecretStore())
    let securityStore = SecurityStore.security(secretStore: KeychainSecretStore())
    let homeStore = HomeStore.home(secretStore: KeychainSecretStore())
    /// Terminal sessions (SSH, Proxmox consoles): a reconnection asks Face ID
    /// every time.
    @ObservationIgnored private(set) lazy var terminals = TerminalSessionStore { [lockController] reason in
        await lockController.authenticateForAction(reason: reason, alwaysAsk: true)
    }
    /// Proxmox consoles (node shell, CT, VM terminal or graphical console).
    @ObservationIgnored private(set) lazy var consoles = ConsoleLauncher(proxmox: proxmoxStore, terminals: terminals, lock: lockController)
    /// SSH sessions (off until Settings › SSH turns them on).
    @ObservationIgnored private(set) lazy var ssh = SSHLauncher(terminals: terminals, lock: lockController)

    /// For the App Store rating prompt (`ReviewPrompt`): when this session
    /// started, whether a service failed during it, and when last.
    @ObservationIgnored let launchedAt = Date.now
    @ObservationIgnored private(set) var sessionHadError = false
    @ObservationIgnored private(set) var lastErrorAt: Date?

    func noteSessionError(at date: Date = .now) {
        sessionHadError = true
        lastErrorAt = date
    }

    /// ⌘N (iPad keyboard, Mac): Settings opens the "Add a service" form, then
    /// clears the request.
    var addServiceRequested = false

    /// The keyboard command: only once unlocked and outside the demo, so it
    /// never fires later.
    func requestAddService() {
        guard lockController.state == .unlocked, !DemoMode.isOn else { return }
        addServiceRequested = true
    }

    @ObservationIgnored private let snapshotWriter = SharedSnapshotWriter()
    @ObservationIgnored private let pathObserver = NetworkPathObserver()

    var stores: [any ManagedStore] {
        [proxmoxStore, backupStore, dockerStore, observabilityStore, tailscaleStore, securityStore, homeStore]
    }

    /// Changes whenever a store finishes a refresh or loses its services.
    var refreshStamp: [Date?] { stores.map { $0.lastUpdated } }

    /// Hands every store its services (by family). The tab view does the same
    /// when the list changes; the background refresh, without UI, uses this.
    func configure(from descriptors: [ServiceDescriptor]) {
        proxmoxStore.configure(descriptors.filter { $0.kind == .proxmoxVE })
        backupStore.configure(descriptors.filter { $0.kind == .proxmoxBackupServer })
        dockerStore.configure(descriptors.filter { $0.kind.isDocker })
        observabilityStore.configure(descriptors.filter { $0.kind.isObservability })
        tailscaleStore.configure(descriptors.filter { $0.kind == .tailscale })
        securityStore.configure(descriptors.filter { $0.kind.isSecurity })
        homeStore.configure(descriptors.filter { $0.kind.isHomeService })
    }

    /// A service's credential was replaced in Settings: its store forgets the old
    /// one and asks the service again.
    func credentialChanged(for serviceID: UUID) {
        Task {
            for store in stores {
                await store.credentialChanged(for: serviceID)
            }
        }
    }

    // MARK: - Network path

    /// A VPN toggled or a network switch: every service's session is replaced (its
    /// connections are dead or use the old route), proxy pauses end and the
    /// stores refresh. Tailscale off/on used to be the only way out of a stuck
    /// connection.
    func startObservingNetwork() {
        pathObserver.start { [weak self] in
            self?.networkPathChanged()
        }
    }

    @ObservationIgnored private var lastNetworkReset: Date?
    @ObservationIgnored private var pendingNetworkReset: Task<Void, Never>?
    /// A flapping network (Wi-Fi roaming, VPN reconnecting) resets and reloads
    /// everything at most once per interval; the last change in a burst is
    /// still handled when the interval ends.
    private static let networkResetInterval: TimeInterval = 10

    private func networkPathChanged() {
        let elapsed = lastNetworkReset.map { Date.now.timeIntervalSince($0) } ?? .infinity
        guard elapsed >= Self.networkResetInterval else {
            guard pendingNetworkReset == nil else { return }
            pendingNetworkReset = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.networkResetInterval - elapsed))
                guard !Task.isCancelled, let self else { return }
                self.pendingNetworkReset = nil
                self.networkPathChanged()
            }
            return
        }
        lastNetworkReset = .now
        HTTPSessionPool.shared.resetAll()
        for store in stores where !store.services.isEmpty {
            Task { await store.networkPathChanged() }
        }
    }

    // MARK: - Shared snapshot (widgets, App Intents)

    @ObservationIgnored private var publishTask: Task<Void, Never>?

    /// Writes what the stores currently show for the widgets (no secret, no URL).
    /// Several stores finish a refresh within a second or two: one write for all.
    func publishSnapshot() {
        publishTask?.cancel()
        // Widgets and shortcuts keep the user's last real data during the demo.
        guard !DemoMode.isOn else { return }
        guard SharedSnapshotStore.appGroup() != nil else { return }
        publishTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await snapshotWriter.publish(makeSnapshot())
        }
    }

    /// Writes now and waits for the file (end of a background refresh, app sent
    /// to the background).
    func publishSnapshotNow() async {
        publishTask?.cancel()
        guard !DemoMode.isOn, SharedSnapshotStore.appGroup() != nil else { return }
        await snapshotWriter.publish(makeSnapshot())
    }

    func makeSnapshot(now: Date = .now) -> SharedSnapshot {
        let order = DashboardCard.ordered(UserDefaults.standard.string(forKey: DashboardCard.orderKey) ?? "")
        // The age of the oldest data shown, not the time of writing: the widget's
        // "old data" state must be true.
        let loaded = stores.filter { !$0.services.isEmpty }.compactMap { $0.lastUpdated }
        return SharedSnapshot(
            generatedAt: loaded.min() ?? now,
            families: order.compactMap(family),
            nodes: proxmoxStore.inventory.sharedNodeLoads(),
            containerIssues: dockerStore.inventory.sharedContainerIssues(),
            guests: proxmoxStore.inventory.sharedGuestTargets(),
            containers: dockerStore.inventory.sharedContainerTargets()
        )
    }

    private func family(_ card: DashboardCard) -> SharedSnapshot.Family? {
        let level: HealthLevel?
        let headline: String
        switch card {
        case .proxmox:
            guard !proxmoxStore.services.isEmpty else { return nil }
            let o = proxmoxStore.inventory.overview
            level = proxmoxStore.level
            headline = String(localized: "\(o.nodesOnline)/\(o.nodesTotal) nodes online")
        case .backups:
            guard !backupStore.services.isEmpty else { return nil }
            level = backupStore.level
            headline = String(localized: "\(backupStore.inventory.overview.guestsBackedUp) guests backed up")
        case .docker:
            guard !dockerStore.services.isEmpty else { return nil }
            let o = dockerStore.inventory.overview
            level = dockerStore.level
            headline = String(localized: "\(o.running)/\(o.total) containers running")
        case .observability:
            guard !observabilityStore.services.isEmpty else { return nil }
            level = observabilityStore.level
            headline = String(localized: "\(observabilityStore.inventory.overview.activeAlerts) active alerts")
        case .tailscale:
            guard !tailscaleStore.services.isEmpty else { return nil }
            let o = tailscaleStore.inventory.overview
            level = tailscaleStore.level
            headline = String(localized: "\(o.online)/\(o.total) devices online")
        case .crowdSec:
            guard !securityStore.services(of: .crowdSec).isEmpty else { return nil }
            level = securityStore.level(of: .crowdSec)
            headline = String(localized: "\(securityStore.inventory.overview.activeBans) active bans")
        case .nginxProxyManager:
            guard !securityStore.services(of: .nginxProxyManager).isEmpty else { return nil }
            let o = securityStore.inventory.overview
            level = securityStore.level(of: .nginxProxyManager)
            headline = String(localized: "\(o.hostsEnabled)/\(o.hostsTotal) hosts enabled")
        case .adGuardHome:
            guard !securityStore.services(of: .adGuardHome).isEmpty else { return nil }
            level = securityStore.level(of: .adGuardHome)
            headline = securityStore.inventory.overview.protectionDisabled > 0
                ? String(localized: "Protection is off")
                : String(localized: "Protection on")
        case .homeAssistant:
            guard !homeStore.services(of: .homeAssistant).isEmpty else { return nil }
            level = homeStore.level(of: .homeAssistant)
            let entities = homeStore.inventory.homeAssistants.reduce(0) { $0 + $1.entities.count }
            headline = String(localized: "\(entities) entities")
        case .glances:
            guard !homeStore.services(of: .glances).isEmpty else { return nil }
            level = homeStore.level(of: .glances)
            headline = String(localized: "\(homeStore.inventory.glancesOverview.hosts) hosts")
        }
        return SharedSnapshot.Family(id: card.rawValue, title: card.title, level: SharedSnapshot.Family.Level(level), headline: headline)
    }

    // MARK: - SMART

    /// Last automatic SMART attempt per service, so a failure isn't retried at
    /// every refresh (an hour later at most).
    @ObservationIgnored private var smartAttempts: [UUID: Date] = [:]
    /// Services whose SMART is being read (button or automatic): one read at a
    /// time per service, the button disabled meanwhile.
    private(set) var smartReadsInFlight: Set<UUID> = []
    /// Changes after every SMART read, so screens show the new date and state.
    private(set) var smartReadRevision = 0
    /// The disk health mode of every Proxmox service (`SMARTSettingsStore`),
    /// read at launch: what the screens show and what every read obeys.
    private(set) var smartSettings: [UUID: SMARTSetting] = SMARTSettingsStore.all()

    func smartSetting(for serviceID: UUID) -> SMARTSetting {
        smartSettings[serviceID] ?? SMARTSetting()
    }

    /// Stored at once. Off: the kept reading is forgotten (and with it the
    /// disk notifications of the service).
    func setSMARTSetting(_ setting: SMARTSetting, for serviceID: UUID) {
        SMARTSettingsStore.set(setting, for: serviceID)
        smartSettings = SMARTSettingsStore.all()
        smartReadRevision += 1
        SMARTBackgroundRead.schedule(notBefore: smartRetryNotBefore)
    }

    /// After settings were removed elsewhere (deleted services).
    func reloadSMARTSettings() {
        let stored = SMARTSettingsStore.all()
        guard stored != smartSettings else { return }
        smartSettings = stored
        smartReadRevision += 1
    }

    /// No background task for SMART before this (an hour after a failed or
    /// pending automatic attempt).
    var smartRetryNotBefore: Date? {
        smartAttempts.values.map { $0 + 3_600 }.filter { $0 > .now }.max()
    }

    /// One read of the disks of one service (list with SMART, then pools)
    /// through `DiskHealthAccess`, the only way to `/nodes/{node}/disks/*`: nil
    /// when the mode doesn't allow it at this moment. `background`: the token
    /// is read for this call only (`singleReadClient`); otherwise only on
    /// screen. Throws the service's error (already reported to its store).
    @discardableResult
    func readSMART(of serviceID: UUID, at moment: SMARTPolicy.Moment, background: Bool = false, timeout: Double = 20) async throws -> SMARTReading? {
        guard smartReadsInFlight.insert(serviceID).inserted else { return nil }
        defer {
            smartReadsInFlight.remove(serviceID)
            smartReadRevision += 1
        }
        let resources = proxmoxStore.inventory.resources(of: serviceID)
        guard !resources.isEmpty,
              SMARTPolicy.readsSMART(at: moment, setting: smartSetting(for: serviceID), lastRead: SMARTReadingStore.shared.lastRead(for: serviceID))
        else { return nil }
        let client = background ? await proxmoxStore.singleReadClient(for: serviceID) : await proxmoxStore.client(for: serviceID)
        guard let client else { return nil }
        do {
            return try await DiskHealthAccess.read(at: moment, serviceID: serviceID, client: client, resources: resources, timeout: timeout)
        } catch {
            // Same as the screens: a refused token pauses the service.
            let state = ServiceLoadState(error: error)
            if state.pausesRequests { proxmoxStore.reportRejectedToken(for: serviceID, state: state) }
            throw error
        }
    }

    /// Reads SMART for the Proxmox services in automatic mode whose time has
    /// passed today and that weren't read today (`SMARTPolicy`). Nothing else
    /// ever runs smartctl: not the refreshes, not the widgets. Stops when
    /// cancelled (the app left the screen, the background task expired).
    func readDueSMART(at moment: SMARTPolicy.Moment, timeout: Double = 20) async {
        guard !DemoMode.isOn else { return }
        defer { SMARTBackgroundRead.schedule(notBefore: smartRetryNotBefore) }
        for service in proxmoxStore.services {
            if Task.isCancelled { break }
            let now = Date.now
            guard SMARTPolicy.readsSMART(at: moment, setting: smartSetting(for: service.id), lastRead: SMARTReadingStore.shared.lastRead(for: service.id), now: now) else { continue }
            if let attempt = smartAttempts[service.id], now.timeIntervalSince(attempt) < 3_600 { continue }
            smartAttempts[service.id] = now
            _ = try? await readSMART(of: service.id, at: moment, background: moment == .scheduledTask, timeout: timeout)
        }
    }

    /// The background task asked for the chosen time: the Proxmox services are
    /// refreshed (for their nodes), then SMART is read where due, then the disk
    /// notifications are evaluated. Secrets are dropped before returning.
    func scheduledSMARTRead() async {
        guard UIApplication.shared.isProtectedDataAvailable, !DemoMode.isOn, AppModelContainer.shared != nil else {
            SMARTBackgroundRead.schedule(notBefore: .now + 3_600)
            return
        }
        if UIApplication.shared.applicationState == .background { proxmoxStore.enterBackground() }
        await runScheduledSMARTRead()
        if UIApplication.shared.applicationState == .background { await proxmoxStore.dropSecrets() }
    }

    private func runScheduledSMARTRead() async {
        guard let container = AppModelContainer.shared else { return }
        let configs = (try? ModelContext(container).fetch(FetchDescriptor<ServiceConfig>(sortBy: [SortDescriptor(\.name)]))) ?? []
        proxmoxStore.configure(configs.uniqued(by: \.id).compactMap { config in
            guard config.kind == .proxmoxVE, let url = config.url else { return nil }
            return ServiceDescriptor(id: config.id, kind: config.kind, name: config.name, url: url)
        })
        guard !proxmoxStore.services.isEmpty else { return }
        await proxmoxStore.refreshInBackground(timeout: BackgroundRefresh.serviceTimeout)
        guard !Task.isCancelled else { return }
        await readDueSMART(at: .scheduledTask, timeout: BackgroundRefresh.serviceTimeout)
        await observeConditions(deliver: UIApplication.shared.applicationState == .background)
    }

    // MARK: - Background refresh

    /// Short refresh while the app is in the background: reloads every service,
    /// updates the shared snapshot and the widgets. Tokens are read from the
    /// Keychain (possible only while the device is unlocked) and not kept.
    func backgroundRefresh() async {
        BackgroundRefresh.schedule()
        guard UIApplication.shared.isProtectedDataAvailable, !DemoMode.isOn else { return }
        // A cold launch for this task has no scene phase: make sure no store caches
        // tokens or runs a foreground refresh.
        let inBackground = UIApplication.shared.applicationState == .background
        if inBackground {
            for store in stores { store.enterBackground() }
        }
        guard let container = AppModelContainer.shared else { return }
        let context = ModelContext(container)
        // Same order as the tab view (by name): no needless reconfiguration.
        let configs = (try? context.fetch(FetchDescriptor<ServiceConfig>(sortBy: [SortDescriptor(\.name)]))) ?? []
        configure(from: configs.uniqued(by: \.id).compactMap { config in
            config.url.map { ServiceDescriptor(id: config.id, kind: config.kind, name: config.name, url: $0) }
        })
        let before = refreshStamp
        await withTaskGroup(of: Void.self) { group in
            for store in stores where !store.services.isEmpty {
                // Services in parallel, 15 s each at most: the whole refresh stays
                // within the ~30 s iOS grants. A store whose refresh is cancelled
                // (expiry) keeps its previous data.
                group.addTask { await store.refreshInBackground(timeout: BackgroundRefresh.serviceTimeout) }
            }
        }
        // Only new data is published (an unchanged snapshot keeps its real age).
        if !Task.isCancelled, refreshStamp != before {
            await publishSnapshotNow()
            // New problems become local notifications (only in the background).
            await observeConditions(deliver: UIApplication.shared.applicationState == .background)
        }
        // Nothing secret stays in memory while suspended (tokens, OAuth/NPM tokens).
        if UIApplication.shared.applicationState == .background {
            for store in stores { await store.dropSecrets() }
        }
    }
}

enum BackgroundRefresh {
    /// Also listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    nonisolated static let identifier = "fr.antxis.apple.labwatch.refresh"
    /// Upper bound per service during a background refresh.
    nonisolated static let serviceTimeout: Double = 15

    /// Asks iOS for a refresh in about 30 minutes; iOS decides when (or whether)
    /// it actually runs.
    /// Submitted off the main thread, as BGTaskScheduler asks.
    static func schedule() {
        Task.detached(priority: .utility) {
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = Date.now.addingTimeInterval(30 * 60)
            // Best effort: a refused request only means no background refresh.
            try? await BGTaskScheduler.shared.submitTaskRequest(request)
        }
    }
}

/// The background read of SMART at the chosen time (automatic mode). iOS
/// decides when it really runs; the app also reads at its first opening after
/// that time.
enum SMARTBackgroundRead {
    /// Also listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    nonisolated static let identifier = "fr.antxis.apple.labwatch.smart"

    /// For the earliest next chosen time among the services in automatic mode
    /// (not before `notBefore`, after a failed attempt); cancelled when none is.
    static func schedule(notBefore: Date? = nil) {
        let services = SMARTSettingsStore.all().map { (setting: $0.value, lastRead: SMARTReadingStore.shared.lastRead(for: $0.key)) }
        let date = SMARTPolicy.nextBackgroundDate(services).map { max($0, notBefore ?? $0) }
        Task.detached(priority: .utility) {
            guard let date else {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
                return
            }
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = date
            try? await BGTaskScheduler.shared.submitTaskRequest(request)
        }
    }
}

/// Writes the shared snapshot when something changed (or every 15 minutes, so
/// the widget's "last data" time stays true), and reloads the widgets only when
/// what they show changed. Encoding and writing happen off the main actor.
@MainActor
final class SharedSnapshotWriter {
    private var lastPublished: SharedSnapshot?
    private let minimumInterval: TimeInterval = 15 * 60
    /// Writes run one after the other, in publication order.
    private var lastWrite: Task<Bool, Never>?
    private var generation = 0

    func publish(_ snapshot: SharedSnapshot) async {
        // App Group not enabled yet (capability to add in Xcode): nothing to share.
        guard let store = SharedSnapshotStore.appGroup() else { return }
        let refreshDue = lastPublished.map { snapshot.generatedAt.timeIntervalSince($0.generatedAt) >= minimumInterval } ?? true
        let widgetsChanged = lastPublished.map { !$0.hasSameWidgetContent(as: snapshot) } ?? true
        let intentsChanged = lastPublished.map { !$0.hasSameContent(as: snapshot) } ?? true
        guard refreshDue || widgetsChanged || intentsChanged else { return }
        generation &+= 1
        let myGeneration = generation
        let previous = lastWrite
        let write = Task.detached(priority: .utility) { () -> Bool in
            _ = await previous?.value
            return (try? store.write(snapshot)) != nil
        }
        lastWrite = write
        let written = await write.value
        // A failed write is retried at the next publication; a newer one wins.
        guard written, myGeneration == generation else { return }
        lastPublished = snapshot
        if refreshDue || widgetsChanged {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
