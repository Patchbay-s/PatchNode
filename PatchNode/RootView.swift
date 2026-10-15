import SwiftUI
import SwiftData
import StoreKit
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLockController.self) private var lockController
    @Environment(ProxmoxStore.self) private var proxmoxStore
    @Environment(DockerStore.self) private var dockerStore
    @Environment(ObservabilityStore.self) private var observabilityStore
    @Environment(BackupStore.self) private var backupStore
    @Environment(TailscaleStore.self) private var tailscaleStore
    @Environment(SecurityStore.self) private var securityStore
    @Environment(HomeStore.self) private var homeStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(ActionLog.self) private var actionLog
    @Environment(\.requestReview) private var requestReview
    @AppStorage(DemoMode.key) private var demoMode = false
    @AppStorage(TabSelection.storageKey) private var storedTabs = ""
    @AppStorage(DashboardCard.orderKey) private var storedOrder = ""
    /// Tabs and dashboard order as synced through iCloud (`CloudReconciliation.syncedKeys`).
    @Query private var syncedSettings: [SyncedSetting]
    /// The user's services, to clean the token of one deleted on another device.
    @Query private var services: [ServiceConfig]
    /// Values just taken from iCloud: their UserDefaults change isn't a local edit.
    @State private var adoptedSettings: [String: String] = [:]
    /// The automatic SMART read started at opening, cancelled in the background.
    @State private var smartTask: Task<Void, Never>?
    /// Mac: a window left inactive (behind another app) locks after a while.
    @State private var inactiveLockTask: Task<Void, Never>?

    private var stores: [any ManagedStore] {
        [proxmoxStore, backupStore, dockerStore, observabilityStore, tailscaleStore, securityStore, homeStore]
    }

    var body: some View {
        ZStack {
            if lockController.state == .unlocked {
                MainTabView()
            }
            if lockController.state != .unlocked {
                LockScreenView(
                    state: lockController.state,
                    offersDemo: lockController.authenticationUnavailable,
                    onRetry: { Task { await lockController.unlock() } },
                    onDemo: {
                        if !demoMode { DemoMode.enter(context: modelContext) }
                        lockController.unlockForDemo()
                    }
                )
            } else if !scenePhase.isOnScreen {
                PrivacyCoverView()
            }
        }
        // iCloud sync: a value from another device is adopted, a change made here
        // is published (no write when both agree, so devices never ping-pong).
        .onChange(of: syncedSettings.map(\.snapshot), initial: true) { reconcileSettings(changed: []) }
        .onChange(of: storedTabs) { _, value in localSettingChanged(TabSelection.storageKey, to: value) }
        .onChange(of: storedOrder) { _, value in localSettingChanged(DashboardCard.orderKey, to: value) }
        .onChange(of: Set(services.map(\.id)), initial: true) { _, ids in
            purgeOrphanTokens()
            // SMART settings of services deleted elsewhere (never on an empty store).
            if !ids.isEmpty, !demoMode {
                SMARTSettingsStore.retain(only: ids)
                SMARTReadingStore.shared.retain(only: ids)
                model.reloadSMARTSettings()
            }
        }
        .onChange(of: demoMode, initial: true) { _, demo in PatchNodeTips.demoMode = demo }
        // Every finished refresh updates the widgets' shared snapshot.
        .onChange(of: model.refreshStamp) {
            model.publishSnapshot()
            // On screen, problems count as seen: they won't be notified later. Not
            // while a background refresh runs (it notifies itself). On the Mac, a
            // window behind another app is still on screen.
            if scenePhase.isOnScreen {
                Task { await model.observeConditions(deliver: false) }
                // Automatic SMART: the first opening after the chosen time. On
                // screen only: cancelled when the app leaves it.
                if smartTask == nil {
                    smartTask = Task {
                        await model.readDueSMART(at: .appOpened)
                        smartTask = nil
                    }
                }
                considerReviewPrompt()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            inactiveLockTask?.cancel()
            inactiveLockTask = nil
            switch newPhase {
            case .active:
                purgeOrphanTokens()
                var review = ReviewPromptState.decoded(from: UserDefaults.standard.data(forKey: ReviewPromptState.storageKey))
                review.recordUse()
                UserDefaults.standard.set(review.encoded(), forKey: ReviewPromptState.storageKey)
                for store in stores { store.enterForeground() }
                model.terminals.enterForeground()
                Task { await lockController.sceneDidBecomeActive() }
            case .background:
                lockController.lockImmediately()
                // A ⌘N not yet handled doesn't open the form after the next unlock.
                model.addServiceRequested = false
                for store in stores { store.enterBackground() }
                // Open terminals close after a grace period (sockets die anyway).
                model.terminals.enterBackground()
                // Widgets get the latest figures; iOS may refresh them later.
                Task { await model.publishSnapshotNow() }
                smartTask?.cancel()
                smartTask = nil
                BackgroundRefresh.schedule()
                SMARTBackgroundRead.schedule(notBefore: model.smartRetryNotBefore)
                GrafanaWebSession.clear()
            default:
                // .inactive (app switcher, Face ID sheet): PrivacyCoverView hides content
                // without resetting the lock, so the Face ID prompt can't lock itself out.
                // On the Mac the window stays visible and refreshing (`isOnScreen`):
                // it locks after `MacWindow.inactiveLockDelay`, which also ends polling.
                guard MacWindow.isMac else { break }
                inactiveLockTask = Task {
                    try? await Task.sleep(for: MacWindow.inactiveLockDelay)
                    guard !Task.isCancelled else { return }
                    lockController.lockImmediately()
                    model.addServiceRequested = false
                }
            }
        }
    }

    /// Only while iCloud sync runs, never during the demo (its tabs are its own).
    private func reconcileSettings(changed: Set<String>) {
        guard AppModelContainer.syncStatus == .on, !demoMode else { return }
        if let adopted = try? CloudHousekeeping.reconcileSettings(in: modelContext, changedLocally: changed) {
            adoptedSettings.merge(adopted) { _, new in new }
        }
    }

    /// A service deleted on another device (iCloud sync) leaves its token here:
    /// it goes once the service has stayed missing for `OrphanTokenTracker.grace`
    /// (never when every service is gone).
    /// Without sync, only the list of known services is kept up to date (a local
    /// deletion removes its token itself).
    private func purgeOrphanTokens() {
        guard !demoMode else { return }
        let defaults = UserDefaults.standard
        var tracker = OrphanTokenTracker.decoded(from: defaults.data(forKey: OrphanTokenTracker.storageKey))
        // Only on screen: a locked iPhone (background import) can't delete.
        let purge = tracker.update(current: Set(services.map(\.id)), purging: AppModelContainer.syncStatus == .on && scenePhase == .active)
        defaults.set(tracker.encoded(), forKey: OrphanTokenTracker.storageKey)
        guard !purge.isEmpty else { return }
        Task {
            let keychain = KeychainSecretStore()
            var deleted = Set<UUID>()
            // This device's copy only: a copy synced in iCloud Keychain was
            // removed by the device that deleted the service, if it syncs tokens.
            for id in purge where (try? await keychain.deleteDeviceOnly(for: id)) != nil {
                deleted.insert(id)
            }
            // Forgotten only once really deleted; the others are tried again.
            var current = OrphanTokenTracker.decoded(from: defaults.data(forKey: OrphanTokenTracker.storageKey))
            current.markPurged(deleted)
            defaults.set(current.encoded(), forKey: OrphanTokenTracker.storageKey)
        }
    }

    /// After a refresh on screen: the App Store rating prompt, only after real
    /// positive use (`ReviewPrompt`): never in the demo, after an error or an
    /// action, right after launch, nor twice for the same version.
    private func considerReviewPrompt() {
        let now = Date.now
        if stores.contains(where: { $0.states.values.contains(where: \.isFailure) }) {
            model.noteSessionError(at: now)
        }
        let defaults = UserDefaults.standard
        var state = ReviewPromptState.decoded(from: defaults.data(forKey: ReviewPromptState.storageKey))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let moment = ReviewPrompt.Moment(
            appVersion: version,
            serviceCount: Set(services.map(\.id)).count,
            demoMode: demoMode,
            sessionHadError: model.sessionHadError,
            launchedAt: model.launchedAt,
            lastEventAt: [model.lastErrorAt, actionLog.entries.last?.date].compactMap(\.self).max(),
            now: now
        )
        guard lockController.state == .unlocked, ReviewPrompt.shouldAsk(state, at: moment) else { return }
        state.markPrompted(version: version)
        defaults.set(state.encoded(), forKey: ReviewPromptState.storageKey)
        requestReview()
    }

    /// A change that only applies a value from iCloud is not published back.
    private func localSettingChanged(_ key: String, to value: String) {
        if adoptedSettings[key] == value {
            adoptedSettings[key] = nil
            reconcileSettings(changed: [])
        } else {
            reconcileSettings(changed: [key])
        }
    }
}
