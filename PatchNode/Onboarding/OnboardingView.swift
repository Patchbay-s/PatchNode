import SwiftUI
import SwiftData
import PatchNodeCore

/// First launch: what the app does, what it needs, then add a first service or
/// try the demo. Skippable; replayed from Settings > About.
struct OnboardingView: View {
    /// UserDefaults key (a Bool, no secret).
    static let doneKey = "onboardingDone"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var services: [ServiceConfig]
    @AppStorage(OnboardingView.doneKey) private var done = false
    @State private var page = 0
    @State private var addServiceViewModel: AddServiceViewModel?
    private let secretStore: any SecretStore = KeychainSecretStore()

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                welcomePage.tag(0)
                requirementsPage.tag(1)
                startPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if page < 2 {
                        Button("Next") { withAnimation { page += 1 } }
                    }
                }
            }
        }
        .sheet(item: $addServiceViewModel) { viewModel in
            AddServiceView(viewModel: viewModel)
        }
        // The first service saved: the introduction is over.
        .onChange(of: services.count) { oldCount, newCount in
            if newCount > oldCount { finish() }
        }
        .privacyCover()
    }

    private var welcomePage: some View {
        OnboardingPage(
            systemImage: "server.rack",
            title: Text("Your HomeLab at a glance"),
            points: [
                (Image(systemName: "square.grid.2x2"), Text("Proxmox nodes, VMs and containers, backups, Docker, alerts, network and security, home automation: one dashboard.")),
                (Image(systemName: "bell.badge"), Text("What needs attention first: failed tasks, unhealthy containers, full disks, active alerts.")),
                (Image(systemName: "hand.raised"), Text("Actions such as restarting a VM always ask for confirmation and Face ID.")),
            ]
        )
    }

    private var requirementsPage: some View {
        OnboardingPage(
            systemImage: "lock.shield",
            title: Text("Before you start"),
            points: [
                (Image(systemName: "network.badge.shield.half.filled"), Text("PatchNode talks directly to your servers, through your private network or a VPN such as Tailscale or WireGuard.")),
                (Image(systemName: "lock"), Text("HTTPS is required: put your services behind a reverse proxy with a valid certificate.")),
                (Image(systemName: "key"), Text("Use dedicated, read-only tokens. They stay in this iPhone's Keychain; nothing is sent to us.")),
            ]
        )
    }

    private var startPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "plus.circle")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Add your first service")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Each service type explains which token to create. You can also explore a sample HomeLab first: no server is contacted.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button {
                        addServiceViewModel = AddServiceViewModel(secretStore: secretStore, modelContext: modelContext)
                    } label: {
                        Text("Add a service").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        DemoMode.enter(context: modelContext)
                        finish()
                    } label: {
                        Text("Try the demo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button("Later") { finish() }
                }
                .controlSize(.large)
            }
            .padding(24)
            .padding(.bottom, 40)
            .frame(maxWidth: ReadableWidth.form)
            .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        done = true
        dismiss()
    }
}

private struct OnboardingPage: View {
    let systemImage: String
    let title: Text
    let points: [(Image, Text)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                title
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                ForEach(points.indices, id: \.self) { index in
                    Label {
                        points[index].1
                    } icon: {
                        points[index].0
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    .font(.body)
                }
            }
            .padding(24)
            .padding(.bottom, 40)
            .frame(maxWidth: ReadableWidth.form)
            .frame(maxWidth: .infinity)
        }
    }
}
