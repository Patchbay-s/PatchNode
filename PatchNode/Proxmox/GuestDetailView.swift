import SwiftUI
import Charts
import PatchNodeCore
import ProxmoxKit
import DockerKit
import SwiftData
import RemoteAccessKit

struct GuestDetailView: View {
    let item: ProxmoxInventory.Item

    @Environment(ProxmoxStore.self) private var store
    @Environment(BackupStore.self) private var backupStore
    @Environment(SSHLauncher.self) private var ssh
    @Query private var sshHosts: [SSHHost]
    @AppStorage(SSHSettings.enabledKey) private var sshEnabled = false
    @AppStorage(DemoMode.key) private var demoMode = false
    @State private var confirmsEnter = false
    @AppStorage(RefreshSettings.key) private var refreshInterval = RefreshSettings.defaultInterval
    @State private var status: ProxmoxGuestStatus?
    @State private var statusState: ServiceLoadState = .loading
    @State private var points: [ProxmoxRRDPoint] = []
    @State private var historyState: ServiceLoadState = .loading
    /// This screen's own request was refused (401/403): the polling stops asking.
    @State private var statusRefused = false
    @State private var historyRefused = false
    @State private var timeframe: ProxmoxRRDTimeframe = .hour
    @State private var historyLoadedAt: Date?

    /// Swift Charts stays smooth well below this many points per series.
    static let maxChartPoints = 500

    private var resource: ProxmoxResource { item.resource }

    var body: some View {
        List {
            statusSection
            consoleSection
            if let target = ProxmoxActionTarget(item: item) {
                ActionsSection(
                    options: actionOptions,
                    // Service + node + type + VMID: a homonymous node of another
                    // service is another target.
                    targetKey: target.key,
                    targetDescription: targetDescription,
                    serviceName: serviceName,
                    perform: perform
                )
            }
            historySection
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle(Text(verbatim: resource.displayName))
        .polling(every: refreshInterval) {
            if !backupStore.services.isEmpty {
                await backupStore.refresh(ifOlderThan: max(refreshInterval - 5, 5))
            }
            // A refused part isn't asked again by the polling (ban risk); a pull
            // to refresh retries it. The service's own state is left alone: only
            // the refresh of /cluster/resources decides it.
            if !statusRefused { await loadStatus() }
            guard !Task.isCancelled else { return }
            if isHistoryStale && !historyRefused { await loadHistory() }
        }
        .refreshable {
            await loadStatus()
            await loadHistory()
        }
        .onChange(of: timeframe) {
            points = []
            historyState = .loading
            historyLoadedAt = nil
        }
        // Initial load and period changes; cancelled when leaving the screen.
        .task(id: timeframe) {
            await loadHistory()
        }
    }

    // MARK: Console

    /// Terminal (CT, VM with a serial port) or graphical console (VM): needs
    /// VM.Console, Face ID every time. Only while the guest runs.
    @ViewBuilder
    private var consoleSection: some View {
        if let node = resource.node, let vmid = resource.vmid, let type = resource.guestType {
            Section {
                ConsoleButton(
                    target: .guest(node: node, type: type, vmid: vmid),
                    name: resource.displayName,
                    serviceID: item.serviceID, serviceName: serviceName,
                    isAvailable: isRunning
                )
                if sshEnabled || demoMode {
                    if let host = guestSSHHost {
                        Button("SSH", systemImage: "terminal.fill") {
                            Task { await ssh.connect(SSHHostSnapshot(host)) }
                        }
                        .disabled(!isRunning)
                    }
                    if type == .lxc, demoMode || nodeSSHHost != nil {
                        Button("Enter the container", systemImage: "arrow.right.to.line") { confirmsEnter = true }
                            .disabled(!isRunning)
                    }
                }
            } footer: {
                if !isRunning {
                    Text("Start the guest to open its console.")
                }
            }
            .confirmationDialog(
                Text("Enter \(resource.displayName)?"),
                isPresented: $confirmsEnter,
                titleVisibility: .visible
            ) {
                Button("Enter \(resource.displayName) on \(node)") { enterContainer(node: node, vmid: vmid) }
            } message: {
                Text("Opens an SSH session on the node \(node) and runs pct enter \(String(vmid)): a root shell inside the container.")
            }
        }
    }

    /// An SSH host linked to this guest (Settings › SSH).
    private var guestSSHHost: SSHHost? {
        guard let vmid = resource.vmid else { return nil }
        return SSHHostLookup.host(in: sshHosts, link: .proxmoxGuest, serviceID: item.serviceID, target: String(vmid))
    }

    /// An SSH host linked to this guest's node, for `pct enter`.
    private var nodeSSHHost: SSHHost? {
        guard let node = resource.node else { return nil }
        return SSHHostLookup.host(in: sshHosts, link: .proxmoxNode, serviceID: item.serviceID, target: node)
    }

    private func enterContainer(node: String, vmid: Int) {
        let title = "\(resource.displayName) (pct)"
        if demoMode {
            ssh.openDemo(title: title, hostname: resource.displayName)
            return
        }
        guard let host = nodeSSHHost, let command = ProxmoxSSHCommands.enterContainer(vmid: vmid, user: host.username) else { return }
        Task { await ssh.connect(SSHHostSnapshot(host), command: command, title: title) }
    }

    // MARK: Actions

    private var isRunning: Bool { (status?.status ?? resource.status) == "running" }

    /// Start when stopped; Shut down / Reboot / Stop (forced) when running.
    private var actionOptions: [ActionOption] {
        if isRunning {
            return [
                ActionOption(id: ProxmoxGuestAction.shutdown.rawValue, title: String(localized: "action.shutdown", defaultValue: "Shut down"), systemImage: "power", isForced: false),
                ActionOption(id: ProxmoxGuestAction.reboot.rawValue, title: String(localized: "action.reboot", defaultValue: "Reboot"), systemImage: "arrow.clockwise", isForced: false),
                ActionOption(id: ProxmoxGuestAction.stop.rawValue, title: String(localized: "action.forceStop", defaultValue: "Force stop"), systemImage: "stop.fill", isForced: true),
            ]
        }
        return [ActionOption(id: ProxmoxGuestAction.start.rawValue, title: String(localized: "action.start", defaultValue: "Start"), systemImage: "play.fill", isForced: false)]
    }

    /// "VM 100 “web” on pve".
    private var targetDescription: String {
        let type = resource.guestType == .lxc ? String(localized: "CT") : String(localized: "VM")
        return String(localized: "\(type) \(resource.vmid.map(String.init) ?? "?") “\(resource.displayName)” on \(resource.node ?? "?")")
            + (item.serviceName.isEmpty || item.serviceName == resource.node ? "" : " (\(item.serviceName))")
    }

    private var serviceName: String {
        store.services.first { $0.id == item.serviceID }?.name ?? ""
    }

    /// POST once (never retried), then follow the task until it ends.
    private func perform(_ option: ActionOption) async -> ActionOutcome {
        guard let action = ProxmoxGuestAction(rawValue: option.id),
              let target = ProxmoxActionTarget(item: item)
        else { return .failed(String(localized: "This target can't be acted on.")) }
        let outcome: ActionOutcome
        do {
            // Always the client of the service the resource came from.
            let store = self.store
            guard let sent = try await target.perform(action, clients: { [store] id in await store.client(for: id) }) else {
                return .failed(String(localized: "The service is unavailable or paused; nothing was sent."))
            }
            let result = try await sent.client.waitForTask(node: target.node, upid: sent.upid)
            if result.succeeded {
                outcome = .succeeded(String(localized: "Completed (\(result.exitStatus ?? "OK"))."))
            } else {
                outcome = .failed(String(localized: "The task failed: \(result.exitStatus ?? "unknown error")."))
            }
        } catch ServiceProviderError.forbidden {
            outcome = .failed(String(localized: "Insufficient rights: the token needs the VM.PowerMgmt privilege (e.g. the roles PVEAuditor,PatchNodePower on /vms, for the user and the token) to act on VMs and containers."))
        } catch ServiceProviderError.unauthorized {
            outcome = .failed(String(localized: "The token was rejected."))
        } catch ProxmoxActionError.taskTimedOut {
            outcome = .failed(String(localized: "Still running after 2 minutes. Check Recent tasks for the result."))
        } catch is CancellationError {
            outcome = .failed(String(localized: "Follow-up interrupted; the action may still complete. Check Recent tasks."))
        } catch {
            let reason = ServiceLoadState(error: error).message ?? String(localized: "unexpected response")
            outcome = .failed(String(localized: "The action failed: \(reason)."))
        }
        // Show the new state right away; the lists refresh in the background.
        await loadStatus()
        Task { await store.refresh() }
        return outcome
    }

    // MARK: Status

    private var statusSection: some View {
        Section("Status") {
            if let message = statusState.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            LabeledContent("State") {
                HStack(spacing: 6) {
                    GuestStatusIcon(status: status?.status ?? resource.status)
                    Text(verbatim: status?.status ?? resource.status ?? "–")
                }
            }
            LabeledContent("Type", value: resource.guestType == .lxc
                           ? String(localized: "Container (LXC)")
                           : String(localized: "Virtual machine (QEMU)"))
            LabeledContent("ID", value: resource.vmid.map(String.init) ?? "–")
            if !item.serviceName.isEmpty {
                LabeledContent("Service", value: item.serviceName)
            }
            LabeledContent("Node", value: resource.node ?? "–")
            LabeledContent("Uptime", value: Format.uptime(status?.uptime ?? resource.uptime))
            LabeledContent("CPU") {
                let cpus = status?.cpus ?? resource.maxCPU
                if let cpus {
                    Text("\(Format.percent(status?.cpu ?? resource.cpu)) of \(Format.count(cpus)) vCPU")
                } else {
                    Text(Format.percent(status?.cpu ?? resource.cpu))
                }
            }
            LabeledContent("Memory", value: Format.usage(status?.memory ?? resource.memory,
                                                         of: status?.maxMemory ?? resource.maxMemory))
            LabeledContent("Disk size", value: Format.bytes(status?.maxDisk ?? resource.maxDisk))
            if let haState = status?.haState {
                LabeledContent("High availability", value: haState)
            }
            if let lock = status?.lock {
                LabeledContent("Lock", value: lock)
            }
            if !backupStore.services.isEmpty, let vmid = resource.vmid, let type = resource.guestType {
                LabeledContent("Last backup") {
                    if let backup = backupStore.inventory.lastBackup(vmid: vmid, type: type) {
                        Text(backup.date, format: .relative(presentation: .named))
                            .foregroundStyle(Date.now.timeIntervalSince(backup.date) > PBSInventory.staleBackupAge ? Color.orange : Color.primary)
                    } else if backupStore.hasLoadedOnce {
                        Text("None found").foregroundStyle(.orange)
                    } else {
                        Text(verbatim: "–")
                    }
                }
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        Section("History") {
            Picker("Period", selection: $timeframe) {
                Text("Hour").tag(ProxmoxRRDTimeframe.hour)
                Text("Day").tag(ProxmoxRRDTimeframe.day)
                Text("Week").tag(ProxmoxRRDTimeframe.week)
            }
            .pickerStyle(.segmented)

            if let message = historyState.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if points.isEmpty {
                if historyState == .loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("No history available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                MetricChart(
                    title: Text("CPU"),
                    samples: series(String(localized: "CPU"), \.cpu),
                    yDomain: 0...1,
                    format: { Format.percent($0) }
                )
                MetricChart(
                    title: Text("Memory"),
                    samples: series(String(localized: "Used"), \.memoryUsed),
                    yDomain: memoryDomain,
                    format: { Format.bytes($0) }
                )
                MetricChart(
                    title: Text("Network"),
                    samples: series(String(localized: "In"), \.networkIn)
                        + series(String(localized: "Out"), \.networkOut),
                    format: { Format.rate($0) }
                )
                MetricChart(
                    title: Text("Disk I/O"),
                    samples: series(String(localized: "Read"), \.diskRead)
                        + series(String(localized: "Write"), \.diskWrite),
                    format: { Format.rate($0) }
                )
            }
        }
    }

    /// rrddata only gains a point per step (1 min, 30 min, 3 h): reloading more
    /// often returns the same data.
    private var isHistoryStale: Bool {
        guard let historyLoadedAt else { return false }
        let step: TimeInterval = switch timeframe {
        case .hour: 60
        case .day: 30 * 60
        case .week: 3 * 60 * 60
        }
        return Date.now.timeIntervalSince(historyLoadedAt) >= step
    }

    private var memoryDomain: ClosedRange<Double>? {
        guard let total = points.compactMap(\.memoryTotal).max(), total > 0 else { return nil }
        return 0...total
    }

    /// One downsampled series; points without a value for this metric are skipped.
    private func series(_ name: String, _ value: KeyPath<ProxmoxRRDPoint, Double?>) -> [ChartSample] {
        let samples = points.compactMap { point in
            point[keyPath: value].map { ChartSample(series: name, time: point.time, value: $0) }
        }
        return downsampleLTTB(
            samples,
            threshold: Self.maxChartPoints,
            x: { $0.time.timeIntervalSince1970 },
            y: { $0.value }
        )
    }

    // MARK: Loading

    /// Why the store has no client for this service (paused, or no token).
    private var pausedServiceState: ServiceLoadState {
        if let state = store.states[item.serviceID], state.pausesRequests { return state }
        return .unauthorized
    }

    private func loadStatus() async {
        guard let node = resource.node, let vmid = resource.vmid, let type = resource.guestType else {
            statusState = .failed
            return
        }
        guard let client = await store.client(for: item.serviceID) else {
            // The service is paused: say why, and try again once it resumes.
            statusState = pausedServiceState
            return
        }
        do {
            status = try await client.guestStatus(node: node, type: type, vmid: vmid)
            statusState = .loaded
            statusRefused = false
        } catch is CancellationError {
            return
        } catch {
            statusState = ServiceLoadState(error: error)
            statusRefused = statusState.pausesRequests
        }
    }

    private func loadHistory() async {
        guard let node = resource.node, let vmid = resource.vmid, let type = resource.guestType else {
            historyState = .failed
            return
        }
        guard let client = await store.client(for: item.serviceID) else {
            historyState = pausedServiceState
            return
        }
        let requested = timeframe
        do {
            let loaded = try await client.guestRRD(node: node, type: type, vmid: vmid, timeframe: requested)
            // Ignore a late answer for a period the user already switched away from.
            guard requested == timeframe else { return }
            points = loaded.sorted { $0.time < $1.time }
            historyState = .loaded
            historyRefused = false
            historyLoadedAt = .now
        } catch is CancellationError {
            return
        } catch {
            guard requested == timeframe else { return }
            historyState = ServiceLoadState(error: error)
            historyRefused = historyState.pausesRequests
        }
    }
}

nonisolated struct ChartSample: Identifiable {
    let series: String
    let time: Date
    let value: Double
    var id: String { "\(series)-\(time.timeIntervalSince1970)" }
}

struct MetricChart: View {
    let title: Text
    let samples: [ChartSample]
    var yDomain: ClosedRange<Double>?
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title.font(.subheadline.bold())
            if samples.isEmpty {
                Text("No data for this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(by: .value("Series", sample.series))
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: domain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(format(number))
                            }
                        }
                    }
                }
                .frame(height: 160)
                // One element for VoiceOver instead of one per point.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(Text(chartSummary(
                    Dictionary(grouping: samples, by: \.series)
                        .sorted { $0.key < $1.key }
                        .map { ($0.key, $0.value.sorted { $0.time < $1.time }.map(\.value)) },
                    format: format
                )))
            }
        }
        .padding(.vertical, 4)
    }

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let maximum = samples.map(\.value).max() ?? 0
        guard maximum > 0, maximum.isFinite else { return 0...1 }
        let upper = maximum * 1.1
        return 0...(upper.isFinite ? upper : maximum)
    }
}
