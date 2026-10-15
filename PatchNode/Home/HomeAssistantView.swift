import SwiftUI
import SwiftData
import TipKit
import PatchNodeCore
import HomeServicesKit

/// Home Assistant: the entities the user chose, and the chosen scenes and
/// scripts, each triggered only after a confirmation naming it.
struct HomeAssistantView: View {
    @Environment(HomeStore.self) private var store
    @Query(sort: \HomeAssistantPin.sortOrder) private var pins: [HomeAssistantPin]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    @State private var pickerService: ServiceDescriptor?

    var body: some View {
        List {
            ServiceErrorsSection(services: store.services(of: .homeAssistant), states: store.states, pauses: store.pauses)
            ForEach(store.services(of: .homeAssistant)) { service in
                serviceSections(service)
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: "Home Assistant"))
        .tabBarClearance()
        .overlay {
            if !store.hasLoadedOnce && store.isRefreshing {
                ProgressView("Loading…")
            }
        }
        .sheet(item: $pickerService) { service in
            HomeAssistantEntityPicker(service: service)
        }
        .refreshable { await store.refresh(force: true) }
        .polling(every: refreshInterval) { await store.refresh(ifOlderThan: max(refreshInterval - 5, 5)) }
    }

    @ViewBuilder
    private func serviceSections(_ service: ServiceDescriptor) -> some View {
        let item = store.inventory.homeAssistant(service.id)
        // One per entity: an iCloud sync can store a pin twice.
        let servicePins = pins.uniqued(by: \.pinKey).filter { $0.serviceID == service.id }
        let entityPins = servicePins.filter { !Self.isActivatable($0.entityID) }
        let actionPins = servicePins.filter { Self.isActivatable($0.entityID) }

        Section {
            if servicePins.isEmpty {
                Text("No entities chosen yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entityPins) { pin in
                EntityRow(entityID: pin.entityID, entity: item?.entity(pin.entityID))
            }
            .onDelete { offsets in
                for index in offsets {
                    try? modelContext.deletePin(serviceID: entityPins[index].serviceID, entityID: entityPins[index].entityID)
                }
                try? modelContext.save()
            }
            Button("Choose entities", systemImage: "checklist") {
                HomeEntitiesTip().invalidate(reason: .actionPerformed)
                pickerService = service
            }
            .popoverTip(HomeEntitiesTip())
            .disabled(item == nil)
        } header: {
            Text(verbatim: service.name)
        }

        ForEach(actionPins) { pin in
            // Plain values: the closure below runs after the confirmation, when the
            // SwiftData pin might already be deleted.
            let entityID = pin.entityID
            let entity = item?.entity(entityID)
            let name = entity?.name ?? entityID
            ActionsSection(
                options: [ActionOption(
                    id: "activate",
                    title: entityID.hasPrefix("scene.")
                        ? String(localized: "Activate scene")
                        : String(localized: "Run script"),
                    systemImage: entityID.hasPrefix("scene.") ? "sparkles" : "play.circle",
                    isForced: false
                )],
                targetKey: "\(service.id.uuidString)|\(entityID)",
                targetDescription: "“\(name)”",
                serviceName: service.name,
                header: Text(verbatim: name),
                perform: { _ in await activate(entityID, on: service) }
            )
        }
    }

    private static func isActivatable(_ entityID: String) -> Bool {
        entityID.hasPrefix("scene.") || entityID.hasPrefix("script.")
    }

    private func activate(_ entityID: String, on service: ServiceDescriptor) async -> ActionOutcome {
        guard let client = await store.homeAssistantClient(for: service.id) else {
            return .failed(String(localized: "The token was rejected. Requests are paused: fix the token, then pull to refresh."))
        }
        do {
            try await client.activate(entityID: entityID)
            Task { await store.refresh(force: false) }
            return .succeeded(String(localized: "Done"))
        } catch {
            let state = ServiceLoadState(error: error)
            store.reportRejectedToken(for: service.id, state: state)
            switch state {
            case .unauthorized, .forbidden:
                return .failed(String(localized: "Refused: the Home Assistant user can't call this service."))
            case .unreachable:
                return .failed(String(localized: "No answer in time. Check in Home Assistant whether it ran; nothing was sent again."))
            default:
                return .failed(String(localized: "Home Assistant returned an unexpected response."))
            }
        }
    }
}

private struct EntityRow: View {
    let entityID: String
    let entity: HAEntity?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entity?.name ?? entityID)
                if let changed = entity?.lastChanged {
                    Text(changed, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let entity {
                Text(verbatim: entity.displayState)
                    .monospacedDigit()
                    .foregroundStyle(entity.isUnavailable ? Color.orange : Color.primary)
            } else {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Searchable list of every entity; tapping one adds it to the screen or removes it.
struct HomeAssistantEntityPicker: View {
    let service: ServiceDescriptor
    @Environment(HomeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HomeAssistantPin.sortOrder) private var pins: [HomeAssistantPin]
    @State private var searchText = ""
    /// `searchText` once typing pauses: the filter runs once per pause, not per key.
    @State private var query = ""
    @State private var domain = "all"

    /// Rows rendered at once; the search narrows the rest.
    static let maxRows = 300

    var body: some View {
        // Computed once per render and shared by every row.
        let results = filtered
        let pinned = pinnedIDs
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $domain) {
                        Text("All").tag("all")
                        Text("Sensors").tag("sensor")
                        Text("Lights").tag("light")
                        Text("Switches").tag("switch")
                        Text("Scenes").tag("scene")
                        Text("Scripts").tag("script")
                    }
                }
                Section {
                    ForEach(results.prefix(Self.maxRows)) { entity in
                        Button {
                            toggle(entity)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: entity.name).foregroundStyle(Color.primary)
                                    Text(verbatim: entity.id)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if pinned.contains(entity.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(pinned.contains(entity.id) ? .isSelected : [])
                    }
                } footer: {
                    if results.count > Self.maxRows {
                        Text("\(results.count - Self.maxRows) more: refine the search.")
                    } else {
                        Text("Scenes and scripts get a button; they run only after a confirmation.")
                    }
                }
            }
            .navigationTitle("Choose entities")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Search entities"))
            .task(id: searchText) {
                // Debounce: cancelled by the next keystroke.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                query = searchText.trimmingCharacters(in: .whitespaces)
            }
            .privacyCover()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var pinnedIDs: Set<String> {
        Set(pins.filter { $0.serviceID == service.id }.map(\.entityID))
    }

    private var filtered: [HAEntity] {
        let entities = store.inventory.homeAssistant(service.id)?.entities ?? []
        guard domain != "all" || !query.isEmpty else { return entities }
        return entities.filter { entity in
            (domain == "all" || entity.domain == domain)
                && (query.isEmpty || entity.name.localizedStandardContains(query) || entity.id.localizedStandardContains(query))
        }
    }

    private func toggle(_ entity: HAEntity) {
        if pins.contains(where: { $0.serviceID == service.id && $0.entityID == entity.id }) {
            try? modelContext.deletePin(serviceID: service.id, entityID: entity.id)
        } else {
            let next = (pins.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(HomeAssistantPin(serviceID: service.id, entityID: entity.id, sortOrder: next))
        }
        try? modelContext.save()
    }
}

struct HomeAssistantCard: View {
    let store: HomeStore
    let pins: [HomeAssistantPin]

    var body: some View {
        DashboardCardShell(
            title: Text(verbatim: "Home Assistant"),
            systemImage: "house",
            level: store.level(of: .homeAssistant),
            hasLoadedOnce: store.hasLoadedOnce,
            failures: store.failures(kind: .homeAssistant),
            lastUpdated: store.lastUpdated
        ) {
            let serviceIDs = Set(store.services(of: .homeAssistant).map(\.id))
            let shown = pins
                .uniqued(by: \.pinKey)
                .filter { serviceIDs.contains($0.serviceID) && !$0.entityID.hasPrefix("scene.") && !$0.entityID.hasPrefix("script.") }
                .prefix(4)
            if shown.isEmpty {
                Text("Choose entities to show them here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(shown)) { pin in
                let entity = store.inventory.homeAssistant(pin.serviceID)?.entity(pin.entityID)
                HStack {
                    Text(verbatim: entity?.name ?? pin.entityID).lineLimit(1)
                    Spacer()
                    Text(verbatim: entity?.displayState ?? "–")
                        .monospacedDigit()
                }
            }
        }
    }
}
