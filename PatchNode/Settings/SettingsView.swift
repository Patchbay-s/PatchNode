import SwiftUI
import SwiftData
import TipKit
import PatchNodeCore
import ProxmoxKit
import DockerKit

struct SettingsView: View {
    @Query(sort: \ServiceConfig.name) private var services: [ServiceConfig]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var model
    @Environment(AppLockController.self) private var lockController
    @AppStorage(DemoMode.key) private var demoMode = false
    @AppStorage(IntentActionSettings.key) private var intentActions = false
    @State private var addServiceViewModel: AddServiceViewModel?
    @State private var serviceToDelete: ServiceConfig?
    @State private var deleteError: String?
    /// Services whose deletion is in flight: hidden so they can't be deleted twice.
    @State private var deletingIDs: Set<UUID> = []
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Refresh interval", selection: $refreshInterval) {
                        ForEach(RefreshSettings.options, id: \.self) { seconds in
                            Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                                .tag(seconds)
                        }
                    }
                } footer: {
                    Text("Data refreshes only while the app is open and the screen is visible.")
                }
                Section {
                    TipView(TabsTip())
                    NavigationLink {
                        TabsSettingsView()
                            .onAppear { TabsTip().invalidate(reason: .actionPerformed) }
                    } label: {
                        Label("Tabs", systemImage: "dock.rectangle")
                    }
                } footer: {
                    Text("Choose up to 4 screens for the tab bar; the others open from their dashboard card.")
                }
                Section {
                    NavigationLink {
                        ActionLogView()
                    } label: {
                        Label("Actions this session", systemImage: "list.bullet.clipboard")
                    }
                    Toggle(isOn: Binding(get: { intentActions }, set: setIntentActions)) {
                        Label("Actions from Siri and Shortcuts", systemImage: "waveform")
                    }
                } footer: {
                    Text("Every action asks for confirmation, and for Face ID again after 5 minutes. The log is kept only until the app quits. Siri and Shortcuts ask only for the iPhone to be unlocked, then a confirmation: leave their actions off unless you need them.")
                }
                Section {
                    NavigationLink {
                        ConfigurationTransferView(secretStore: secretStore)
                    } label: {
                        Label("Export and import", systemImage: "arrow.up.arrow.down.square")
                    }
                } footer: {
                    Text("Your services as a file or a QR code, without tokens, to set up another iPhone or keep a copy.")
                }
                Section {
                    TipView(ICloudTip())
                    NavigationLink {
                        CloudSyncView()
                            .onAppear { ICloudTip().invalidate(reason: .actionPerformed) }
                    } label: {
                        Label("iCloud", systemImage: "icloud")
                    }
                } footer: {
                    Text("Your configuration on your other devices, through your own iCloud: off by default.")
                }
                Section {
                    NavigationLink {
                        SSHSettingsView()
                    } label: {
                        Label {
                            Text(verbatim: "SSH")
                        } icon: {
                            Image(systemName: "terminal")
                        }
                    }
                } footer: {
                    Text("A terminal on your own servers, with this device's key: off by default.")
                }
                Section {
                    TipView(NotificationsTip())
                    NavigationLink {
                        NotificationSettingsView()
                            .onAppear { NotificationsTip().invalidate(reason: .actionPerformed) }
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Local alerts after a background refresh, when iOS allows one: off by default.")
                }
                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                } footer: {
                    Text("State of each service and the last 200 requests, to report a connection problem.")
                }
                demoSection
                Section {
                    NavigationLink {
                        HelpSupportView()
                    } label: {
                        Label("Help and support", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
                if demoMode {
                    Section("Services") {
                        Text("Your services are hidden during the demo. Exit the demo to see and edit them.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    servicesSection
                }
            }
            .readableWidth()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !demoMode {
                        Button("Add a service", systemImage: "plus") {
                            addServiceViewModel = AddServiceViewModel(secretStore: secretStore, modelContext: modelContext)
                        }
                    }
                }
            }
            .sheet(item: $addServiceViewModel) { viewModel in
                AddServiceView(viewModel: viewModel)
            }
            // ⌘N from any tab (the tab view switched to Settings).
            .onChange(of: model.addServiceRequested, initial: true) { _, requested in
                guard requested else { return }
                model.addServiceRequested = false
                if !demoMode, addServiceViewModel == nil {
                    addServiceViewModel = AddServiceViewModel(secretStore: secretStore, modelContext: modelContext)
                }
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(
                    get: { serviceToDelete != nil },
                    set: { if !$0 { serviceToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: serviceToDelete
            ) { service in
                Button("Delete \(service.name)", role: .destructive) {
                    Task { await delete(service) }
                }
            } message: { _ in
                Text("Its API token will also be removed from the Keychain.")
            }
            .alert(
                "Deletion failed",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    /// Turning Siri actions on is itself sensitive (they skip PatchNode's Face ID),
    /// so it follows the same rule as an action; turning them off asks nothing.
    private func setIntentActions(_ isOn: Bool) {
        guard isOn else {
            intentActions = false
            return
        }
        Task {
            if await lockController.authenticateForAction(reason: String(localized: "Allow actions from Siri and Shortcuts")) {
                intentActions = true
            }
        }
    }

    private var demoSection: some View {
        Section {
            if demoMode {
                Button("Exit demo", systemImage: "xmark.circle") {
                    DemoMode.exit(context: modelContext, lock: lockController)
                }
            } else {
                Button("Try the demo", systemImage: "sparkles.rectangle.stack") {
                    DemoMode.enter(context: modelContext)
                }
            }
        } header: {
            Text("Demo")
        } footer: {
            Text("A sample HomeLab with every service type, generated on this iPhone: no server is contacted and actions are simulated. Your services are kept and come back when you exit.")
        }
    }

    private var servicesSection: some View {
        Section("Services") {
            if services.isEmpty {
                ContentUnavailableView("No services configured yet.", systemImage: "server.rack")
            }
            // One row per ID: an iCloud sync can store a service twice.
            ForEach(services.uniqued(by: \.id).filter { !deletingIDs.contains($0.id) }) { service in
                Button {
                    edit(service)
                } label: {
                    VStack(alignment: .leading) {
                        Text(service.name).font(.headline)
                        Text(service.urlString).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Edit"))
                .swipeActions {
                    // No direct delete: a confirmation naming the service is required.
                    Button("Delete", systemImage: "trash") {
                        serviceToDelete = service
                    }
                    .tint(.red)
                }
            }
        }
    }

    /// Same form as adding, pre-filled; the type stays fixed.
    private func edit(_ service: ServiceConfig) {
        addServiceViewModel = AddServiceViewModel(
            editing: service, secretStore: secretStore, modelContext: modelContext,
            onCredentialChanged: { [model] id in model.credentialChanged(for: id) }
        )
    }

    private var deleteDialogTitle: String {
        guard let serviceToDelete else { return "" }
        return String(localized: "Delete “\(serviceToDelete.name)”?")
    }

    /// Removes the Keychain token first: if that fails, the service stays listed
    /// instead of leaving an orphaned secret behind.
    private func delete(_ service: ServiceConfig) async {
        let id = service.id
        guard deletingIDs.insert(id).inserted else { return }
        defer { deletingIDs.remove(id) }
        do {
            try await secretStore.delete(for: id)
        } catch {
            deleteError = String(localized: "The API token couldn't be removed from the Keychain. The service was kept.")
            return
        }
        // Charts that queried this Prometheus go with it.
        let favorites = (try? modelContext.fetch(FetchDescriptor<PromQLFavorite>(
            predicate: #Predicate { $0.serviceID == id }
        ))) ?? []
        for favorite in favorites { modelContext.delete(favorite) }
        // Home Assistant entities chosen for this service too.
        let pins = (try? modelContext.fetch(FetchDescriptor<HomeAssistantPin>(
            predicate: #Predicate { $0.serviceID == id }
        ))) ?? []
        for pin in pins { modelContext.delete(pin) }
        if let url = service.url { CertificateRegistry.shared.remove(for: url) }
        SMARTSettingsStore.remove(id)
        model.reloadSMARTSettings()
        // Every copy (an iCloud sync can store a service twice).
        let copies = (try? modelContext.serviceRecords(id: id)) ?? []
        for copy in copies where copy !== service { modelContext.delete(copy) }
        modelContext.delete(service)
        do {
            try modelContext.save()
        } catch {
            deleteError = String(localized: "The service couldn't be deleted.")
        }
    }
}

extension AddServiceViewModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
