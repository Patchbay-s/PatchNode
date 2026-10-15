import SwiftUI
import DockerKit
import PatchNodeCore
import ProxmoxKit

struct ContainerDetailView: View {
    let item: DockerInventory.ContainerItem

    @Environment(DockerStore.self) private var store
    @State private var details: DockerContainerDetails?
    @State private var loadState: ServiceLoadState = .loading
    /// Only the latest load may write its result (pull to refresh during the first load).
    @State private var loadGeneration = 0

    /// Latest state from the inventory (refreshed after an action), else the
    /// snapshot the screen was opened with.
    private var container: DockerContainer {
        store.inventory.containers.first { $0.id == item.id }?.container ?? item.container
    }

    var body: some View {
        List {
            Section("Status") {
                if let message = loadState.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                LabeledContent("State") {
                    HStack(spacing: 6) {
                        ContainerStatusIcon(container: container)
                        Text(verbatim: container.status)
                    }
                }
                LabeledContent("Image", value: container.image)
                LabeledContent("Host", value: item.host.name)
                if let project = container.composeProject {
                    LabeledContent("Stack", value: project)
                }
                if let service = container.composeService {
                    LabeledContent("Compose service", value: service)
                }
                if let uptime = details?.uptime, container.isRunning {
                    LabeledContent("Uptime", value: Format.duration(uptime))
                }
                if let created = container.created {
                    LabeledContent("Created") { Text(created, format: .dateTime) }
                }
                if let details {
                    if let policy = details.restartPolicy, !policy.isEmpty {
                        LabeledContent("Restart policy", value: policy)
                    }
                    if let count = details.restartCount {
                        LabeledContent("Restarts", value: String(count))
                    }
                    if let status = details.healthStatus {
                        LabeledContent("Health check", value: status)
                    }
                    if let streak = details.healthFailingStreak, streak > 0 {
                        LabeledContent("Failed checks in a row", value: String(streak))
                    }
                    if !container.isRunning, let exitCode = details.exitCode {
                        LabeledContent("Exit code", value: String(exitCode))
                    }
                    if details.oomKilled {
                        Label("Killed for lack of memory (OOM)", systemImage: "memorychip")
                            .foregroundStyle(.red)
                    }
                }
            }

            ActionsSection(
                options: actionOptions,
                targetKey: item.id,
                targetDescription: targetDescription,
                serviceName: serviceName,
                perform: perform
            )

            Section {
                NavigationLink {
                    ContainerLogsView(item: item)
                } label: {
                    Label("Logs", systemImage: "text.alignleft")
                }
            }

            if !container.ports.isEmpty {
                Section("Ports") {
                    ForEach(Array(container.ports.enumerated()), id: \.offset) { _, port in
                        Text(verbatim: Self.describe(port))
                            .font(.callout.monospaced())
                    }
                }
            }

            if let details, !details.mounts.isEmpty {
                Section("Volumes") {
                    ForEach(Array(details.mounts.enumerated()), id: \.offset) { _, mount in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: mount.destination ?? "?")
                                .font(.callout.monospaced())
                            HStack {
                                Text(verbatim: mount.source ?? "")
                                if mount.readOnly { Text("read-only") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let details, !details.networks.isEmpty {
                Section("Networks") {
                    ForEach(details.networks, id: \.self) { Text(verbatim: $0) }
                }
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: container.name))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        guard let client = await store.client(for: item.serviceID) else {
            if generation == loadGeneration { loadState = .unauthorized }
            return
        }
        do {
            let loaded = try await client.details(on: item.host, containerID: container.id)
            guard generation == loadGeneration else { return }
            details = loaded
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            loadState = ServiceLoadState(error: error)
            store.reportRejectedToken(for: item.serviceID, state: loadState)
        }
    }

    // MARK: Actions

    private var actionOptions: [ActionOption] {
        if container.isRunning {
            return [
                ActionOption(id: DockerContainerAction.restart.rawValue, title: String(localized: "action.restart", defaultValue: "Restart"), systemImage: "arrow.clockwise", isForced: false),
                ActionOption(id: DockerContainerAction.stop.rawValue, title: String(localized: "action.stop", defaultValue: "Stop"), systemImage: "stop.fill", isForced: false),
            ]
        }
        return [ActionOption(id: DockerContainerAction.start.rawValue, title: String(localized: "action.start", defaultValue: "Start"), systemImage: "play.fill", isForced: false)]
    }

    /// "container “web” on docker-host".
    private var targetDescription: String {
        String(localized: "container “\(container.name)” (\(String(container.id.prefix(12)))) on \(item.host.name)")
    }

    private var serviceName: String {
        store.services.first { $0.id == item.serviceID }?.name ?? ""
    }

    /// POST once (never retried), then refresh the container's state.
    private func perform(_ option: ActionOption) async -> ActionOutcome {
        guard let action = DockerContainerAction(rawValue: option.id) else {
            return .failed(String(localized: "This target can't be acted on."))
        }
        guard let client = await store.client(for: item.serviceID) else {
            return .failed(String(localized: "The service is unavailable or paused; nothing was sent."))
        }
        let outcome: ActionOutcome
        let sentAt = Date.now
        do {
            switch try await client.perform(action, on: item.host, containerID: container.id) {
            case .done: outcome = .succeeded(String(localized: "Done."))
            case .alreadyInState: outcome = .succeeded(String(localized: "Already in that state."))
            }
        } catch ServiceProviderError.unreachable where action != .start {
            // Stop/restart answer only once the container has stopped: a timeout
            // here usually means "still stopping". Check its state, don't resend.
            let confirmed = (try? await client.confirm(action, on: item.host, containerID: container.id, since: sentAt)) ?? false
            outcome = confirmed
                ? .succeeded(String(localized: "Done (confirmed by reading the container's state)."))
                : .failed(String(localized: "No answer in time; the action may still complete. Pull to refresh in a moment."))
        } catch ServiceProviderError.forbidden {
            outcome = .failed(String(localized: "Actions are disabled on this service (read-only socket proxy with POST=0, or a user without the right)."))
        } catch ServiceProviderError.unauthorized {
            store.reportRejectedToken(for: item.serviceID, state: .unauthorized)
            outcome = .failed(String(localized: "The token was rejected."))
        } catch ServiceProviderError.unexpectedStatus(404) {
            outcome = .failed(String(localized: "This container no longer exists."))
        } catch {
            let reason = ServiceLoadState(error: error).message ?? String(localized: "unexpected response")
            outcome = .failed(String(localized: "The action failed: \(reason)."))
        }
        await load()
        // The lists refresh in the background: the result shows right away.
        Task { await store.refresh() }
        return outcome
    }

    static func describe(_ port: DockerPort) -> String {
        let inside = "\(port.privatePort.map(String.init) ?? "?")/\(port.type)"
        guard let publicPort = port.publicPort else { return inside }
        let address = port.ip.map { $0.contains(":") ? "[\($0)]" : $0 } ?? "0.0.0.0"
        return "\(address):\(publicPort) → \(inside)"
    }
}
