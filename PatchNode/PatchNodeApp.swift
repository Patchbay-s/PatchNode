import SwiftUI
import SwiftData
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

@main
struct PatchNodeApp: App {
    @State private var model = AppModel()
    @AppStorage(DemoMode.key) private var demoMode = false

    init() {
        DemoMode.installResponders()
        // iOS crash, hang and performance reports, kept on the device only.
        MetricKitReceiver.shared.start()
        PatchNodeTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            StoreGate {
                RootView()
                    .appEnvironment(model)
                    .task { model.startObservingNetwork() }
            }
            .macMinimumWindowSize()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add a service") { model.requestAddService() }
                    .keyboardShortcut("n")
                    .disabled(model.lockController.state != .unlocked || demoMode)
            }
        }
        // BGAppRefreshTask: iOS decides when; expiry cancels the task.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [model] in
            await model.backgroundRefresh()
        }
        // SMART in automatic mode, at the time chosen per Proxmox service.
        .backgroundTask(.appRefresh(SMARTBackgroundRead.identifier)) { [model] in
            await model.scheduledSMARTRead()
        }
    }
}

/// The app on its store, or the store error screen (M-R2) when it couldn't
/// open. From that screen, only the demo runs, on an empty in-memory store.
private struct StoreGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @AppStorage(DemoMode.key) private var demoMode = false

    var body: some View {
        switch AppModelContainer.state {
        case .ready(let container):
            content()
                .modelContainer(container)
                .task { await AppModelContainer.bindCredentialsIfNeeded() }
        case .failed(let code):
            if demoMode, let fallback = AppModelContainer.demoFallback {
                content().modelContainer(fallback)
            } else {
                StoreErrorView(code: code, offersDemo: AppModelContainer.demoFallback != nil) {
                    // Sample choices aren't seeded: the in-memory store stays empty.
                    demoMode = true
                }
            }
        }
    }
}
