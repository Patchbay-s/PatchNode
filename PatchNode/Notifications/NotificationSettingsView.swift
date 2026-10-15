import SwiftUI
import UIKit
import PatchNodeCore

/// Settings › Notifications: which problems may become a local notification.
/// All off by default; the first switch turned on asks iOS for permission.
struct NotificationSettingsView: View {
    @AppStorage(WatchedKindSettings.storageKey) private var storedKinds = ""
    @State private var denied = false
    @Environment(\.openURL) private var openURL

    private var enabled: Set<WatchedKind> { WatchedKindSettings.decode(storedKinds) }

    var body: some View {
        List {
            Section {
                ForEach(WatchedKind.allCases, id: \.self) { kind in
                    Toggle(LocalNotifications.title(for: kind), isOn: Binding(
                        get: { enabled.contains(kind) },
                        set: { set(kind, on: $0) }
                    ))
                }
            } footer: {
                Text("A notification says only how many problems are new (for example “2 containers are unhealthy”): no name, address or detail, even on the lock screen. Each problem is notified once; one that comes back within 6 hours stays quiet.")
            }
            if denied {
                Section {
                    Button("Allow notifications in Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Notifications are turned off for PatchNode in the iPhone's Settings.")
                }
            }
            Section("When do they arrive?") {
                Text("PatchNode has no server: it checks your services only when iOS lets it refresh in the background. iOS decides when, from how you use the app, the battery and the network: often a few times a day, sometimes not for hours, and never if you force-quit the app. A notification can therefore arrive late, or not at all.")
                Text("Your VPN must be on for the checks to reach your services. When every service is unreachable at once, PatchNode assumes the VPN is off and doesn't notify.")
                Text("For real-time alerting, keep your HomeLab's own alerts (Alertmanager, Uptime Kuma, Home Assistant…).")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .readableWidth()
        .navigationTitle("Notifications")
        .task { denied = await LocalNotifications.isDenied() && !enabled.isEmpty }
    }

    private func set(_ kind: WatchedKind, on: Bool) {
        var kinds = enabled
        if on { kinds.insert(kind) } else { kinds.remove(kind) }
        storedKinds = WatchedKindSettings.encode(kinds)
        guard on else { return }
        Task {
            let allowed = await LocalNotifications.requestAuthorization()
            denied = !allowed
            BackgroundRefresh.schedule()
        }
    }
}
