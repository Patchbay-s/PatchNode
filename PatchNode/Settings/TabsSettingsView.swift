import SwiftUI
import SwiftData
import PatchNodeCore

/// Settings > Tabs: which screens sit in the tab bar (at most 4, Settings always
/// last, so never "More") and in what order. The others open from their
/// dashboard card.
struct TabsSettingsView: View {
    @Query(sort: \ServiceConfig.name) private var services: [ServiceConfig]
    @AppStorage(TabSelection.storageKey) private var storedTabs = ""
    @AppStorage(DemoMode.key) private var demoMode = false

    private var available: [AppScreen] {
        AppScreen.available(for: demoMode ? DemoCatalog.services.map(\.kind) : services.map(\.kind))
    }

    private var tabs: [AppScreen] {
        TabSelection.resolve(stored: TabSelection.decode(storedTabs), available: available)
    }

    var body: some View {
        let tabs = tabs
        let others = available.filter { !tabs.contains($0) }
        List {
            Section {
                ForEach(tabs) { screen in
                    row(screen, tabs: tabs)
                }
                .onMove { source, destination in
                    var reordered = tabs
                    reordered.move(fromOffsets: source, toOffset: destination)
                    storedTabs = TabSelection.encode(reordered)
                }
            } header: {
                Text("Tab bar")
            } footer: {
                Text("Up to \(TabSelection.maxTabs) screens, then Settings. Drag to reorder. The dashboard always stays: the other screens open from its cards.")
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { screen in
                        row(screen, tabs: tabs)
                    }
                } header: {
                    Text("Other screens")
                } footer: {
                    if tabs.count >= TabSelection.maxTabs {
                        Text("The tab bar is full: switch a screen off to add another one.")
                    }
                }
            }
        }
        .readableWidth()
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ screen: AppScreen, tabs: [AppScreen]) -> some View {
        Toggle(isOn: Binding(
            get: { tabs.contains(screen) },
            set: { _ in storedTabs = TabSelection.encode(TabSelection.toggled(screen, in: tabs)) }
        )) {
            Label(screen.title, systemImage: screen.systemImage)
        }
        .disabled(!TabSelection.canToggle(screen, in: tabs))
    }
}
