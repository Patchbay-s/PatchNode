import SwiftUI
import SwiftData
import CloudKit
import PatchNodeCore

/// Settings › iCloud: the configuration through iCloud (SwiftData + CloudKit, the
/// user's private database), and, separately, the tokens through iCloud Keychain.
/// Both off by default. Nothing ever goes to a server of the developer.
struct CloudSyncView: View {
    @Environment(AppLockController.self) private var lockController
    @AppStorage(CloudSyncSettings.key) private var syncConfiguration = false
    @AppStorage(TokenSyncSettings.key) private var syncTokens = false
    @AppStorage(DemoMode.key) private var demoMode = false
    @Query private var services: [ServiceConfig]
    @State private var pendingTokenChoice: Bool?
    /// Services whose token in iCloud Keychain differs from this iPhone's one,
    /// found before turning token sync on.
    @State private var conflicts: Set<UUID> = []
    @State private var isMovingTokens = false
    @State private var tokenError: String?
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var deletionResult: String?

    private let keychain = KeychainSecretStore()
    /// One move at a time, even if the screen is closed and opened again meanwhile.
    private static var isMoving = false

    var body: some View {
        Form {
            if demoMode {
                ContentUnavailableView(
                    "Not available in the demo",
                    systemImage: "sparkles.rectangle.stack",
                    description: Text("Exit the demo to sync your own configuration.")
                )
            } else {
                configurationSection
                tokenSection
                deletionSection
            }
        }
        .readableWidth()
        .navigationTitle("iCloud")
        .confirmationDialog(
            tokenDialogTitle,
            isPresented: Binding(get: { pendingTokenChoice != nil }, set: { if !$0 { pendingTokenChoice = nil } }),
            titleVisibility: .visible,
            presenting: pendingTokenChoice
        ) { enable in
            if enable && !conflicts.isEmpty {
                // An explicit choice: one copy per service survives.
                Button("Keep this iPhone's tokens") {
                    pendingTokenChoice = nil
                    Task { await changeTokenSync(to: true, keepingSynchronized: []) }
                }
                Button("Use the tokens already in iCloud") {
                    let keep = conflicts
                    pendingTokenChoice = nil
                    Task { await changeTokenSync(to: true, keepingSynchronized: keep) }
                }
            } else {
                Button(enable ? String(localized: "Sync tokens with iCloud Keychain") : String(localized: "Keep tokens on this iPhone only"),
                       role: enable ? nil : .destructive) {
                    pendingTokenChoice = nil
                    Task { await changeTokenSync(to: enable, keepingSynchronized: []) }
                }
            }
        } message: { enable in
            if enable && !conflicts.isEmpty {
                Text("iCloud Keychain already holds a different token, saved on another device, for: \(conflictNames). Only one can be kept for each service, on all your devices.")
            } else if enable {
                Text("Your tokens and passwords will be stored in iCloud Keychain, end-to-end encrypted, and available on your devices signed in to the same Apple Account. Anyone who can unlock one of these devices could use them.")
            } else {
                Text("Your tokens and passwords will be removed from iCloud Keychain, and so from your other devices, where they'll have to be entered again. They stay on this iPhone.")
            }
        }
        .confirmationDialog("Delete your iCloud data?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete my iCloud data", role: .destructive) {
                Task { await deleteICloudData() }
            }
        } message: {
            if syncTokens {
                Text("The configuration synced in your iCloud, and your tokens in iCloud Keychain, will be deleted from iCloud and your other devices. This iPhone keeps its configuration and its tokens. Sync is turned off.")
            } else {
                Text("The configuration synced in your iCloud will be deleted. This iPhone keeps its configuration. Sync is turned off.")
            }
        }
        .alert("Tokens couldn't be moved", isPresented: Binding(get: { tokenError != nil }, set: { if !$0 { tokenError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: tokenError ?? "")
        }
        .alert("iCloud data", isPresented: Binding(get: { deletionResult != nil }, set: { if !$0 { deletionResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: deletionResult ?? "")
        }
    }

    private var configurationSection: some View {
        Section {
            Toggle("Sync configuration with iCloud", isOn: $syncConfiguration)
                // Not before this device's tokens are bound to their servers
                // (first launch of 1.1, normally done in a moment).
                .disabled(!syncConfiguration && !CredentialBinding.isDone())
            if let status = statusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(AppModelContainer.syncStatus == .unavailable ? Color.orange : Color.secondary)
            }
        } footer: {
            Text("Services (names and addresses), PromQL charts, Home Assistant entities, tabs and dashboard order, in your own iCloud: the developer has no access to it. Tokens are not included unless you turn on the option below. Refresh interval, notifications and lock stay specific to each device.")
        }
    }

    private var tokenSection: some View {
        Section {
            Toggle("Also sync tokens with iCloud Keychain", isOn: Binding(
                get: { syncTokens },
                set: { enable in Task { await askTokenSync(enable) } }
            ))
            .disabled(isMovingTokens || Self.isMoving)
            if isMovingTokens {
                ProgressView()
            }
        } footer: {
            Text("Off (recommended): tokens and passwords stay in this iPhone's Keychain only, and must be entered on each device. On: they go to iCloud Keychain, end-to-end encrypted by Apple, so your other devices with this option on can use them. Turning it off removes them from iCloud Keychain.")
        }
    }

    private var deletionSection: some View {
        let availability = CloudDataDeletion.availability(syncRunning: AppModelContainer.syncStatus == .on, demo: demoMode)
        return Section {
            Button("Delete my iCloud data", systemImage: "icloud.slash", role: .destructive) {
                confirmsDeletion = true
            }
            .disabled(availability != .available || isDeleting || isMovingTokens)
            if isDeleting {
                ProgressView()
            }
        } footer: {
            if availability == .syncRunning {
                Text("Turn off configuration sync above and open PatchNode again first: while it syncs, it would send everything back.")
            } else {
                Text("Deletes what PatchNode keeps in your iCloud (and your tokens in iCloud Keychain if that option is on), on all your devices. Turn sync off on your other devices first, or they will send their configuration again.")
            }
        }
    }

    private var conflictNames: String {
        let names = services.uniqued(by: \.id).filter { conflicts.contains($0.id) }.map(\.name).sorted()
        return names.formatted(.list(type: .and))
    }

    /// What the toggle will do, compared to what this launch opened.
    private var statusText: String? {
        switch (syncConfiguration, AppModelContainer.syncStatus) {
        case (true, .on), (false, .off):
            return syncConfiguration ? String(localized: "On. Changes reach your other devices when iCloud syncs them, usually within a few minutes.") : nil
        case (true, .unavailable):
            return String(localized: "iCloud couldn't be opened: check that you're signed in to iCloud and that iCloud is allowed for PatchNode. Your configuration on this iPhone is used meanwhile.")
        case (false, .unavailable), (false, .on), (true, .off):
            return String(localized: "Applies the next time PatchNode opens: quit it from the app switcher, then open it again.")
        }
    }

    private var tokenDialogTitle: String {
        pendingTokenChoice == true
            ? String(localized: "Sync tokens with iCloud Keychain?")
            : String(localized: "Stop syncing tokens?")
    }

    /// Enabling: first look for different tokens already in iCloud Keychain, so
    /// the dialog can ask which ones to keep.
    private func askTokenSync(_ enable: Bool) async {
        conflicts = []
        if enable {
            conflicts = (try? await keychain.synchronizedConflicts(ids: Set(services.map(\.id)))) ?? []
        }
        pendingTokenChoice = enable
    }

    /// Face ID first. Enabling: the setting goes on, then the tokens move (reads
    /// look in both places meanwhile). Disabling: the tokens move back while the
    /// setting is still on, then it goes off. A failure leaves every token
    /// readable; the setting stays as it was where the move didn't complete.
    private func changeTokenSync(to enable: Bool, keepingSynchronized: Set<UUID>) async {
        let reason = enable ? String(localized: "Sync tokens with iCloud Keychain") : String(localized: "Stop syncing tokens")
        guard !Self.isMoving, await lockController.authenticateForAction(reason: reason, alwaysAsk: true), !Self.isMoving else { return }
        Self.isMoving = true
        isMovingTokens = true
        defer {
            Self.isMoving = false
            isMovingTokens = false
        }
        // UserDefaults directly: the move outlives this screen if it closes.
        let defaults = UserDefaults.standard
        if enable { defaults.set(true, forKey: TokenSyncSettings.key) }
        do {
            // This device's services only: tokens of services it doesn't know
            // are left where they are.
            try await keychain.moveAll(toSynchronized: enable, ids: Set(services.map(\.id)), keepingSynchronized: keepingSynchronized)
            if !enable { defaults.set(false, forKey: TokenSyncSettings.key) }
        } catch {
            tokenError = String(localized: "Every token is still usable. Try again in a moment.")
        }
        // Token values don't change, except those taken from iCloud.
    }

    /// Confirmation, Face ID, then `CloudDataDeletion.steps`: tokens come back to
    /// this iPhone before iCloud Keychain is emptied, then the CloudKit zone of
    /// the configuration goes, then both options are turned off.
    private func deleteICloudData() async {
        guard !Self.isMoving, await lockController.authenticateForAction(reason: String(localized: "Delete my iCloud data"), alwaysAsk: true),
              !Self.isMoving else { return }
        Self.isMoving = true
        isDeleting = true
        defer {
            Self.isMoving = false
            isDeleting = false
        }
        let defaults = UserDefaults.standard
        do {
            for step in CloudDataDeletion.steps(tokenSyncOn: TokenSyncSettings.isEnabled(defaults)) {
                switch step {
                case .moveTokensToDevice:
                    try await keychain.moveAll(toSynchronized: false, ids: Set(services.map(\.id)))
                case .deleteSyncedTokens:
                    try await keychain.deleteAllSynchronized()
                    // Off now: if the zone can't be deleted, no new token goes back.
                    defaults.set(false, forKey: TokenSyncSettings.key)
                case .deleteConfigurationZone:
                    try await Self.deleteConfigurationZone()
                case .turnSyncOff:
                    defaults.set(false, forKey: TokenSyncSettings.key)
                    defaults.set(false, forKey: CloudSyncSettings.key)
                }
            }
            deletionResult = String(localized: "Your iCloud data was deleted. This iPhone keeps its configuration and its tokens.")
        } catch let error as CKError where error.code == .notAuthenticated {
            deletionResult = String(localized: "Sign in to iCloud on this iPhone to delete your iCloud data.")
        } catch {
            deletionResult = String(localized: "Your iCloud data couldn't be deleted completely. Check your connection and try again.")
        }
    }

    /// The zone SwiftData's CloudKit mirroring writes to, in the user's private
    /// database. Already gone counts as done.
    private static func deleteConfigurationZone() async throws {
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await CKContainer.default().privateCloudDatabase.deleteRecordZone(withID: zone)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return
        }
    }
}
