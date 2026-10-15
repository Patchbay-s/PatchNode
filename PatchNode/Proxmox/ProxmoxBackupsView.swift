import SwiftUI
import PatchNodeCore
import ProxmoxKit

/// Proxmox VE's own backups (vzdump), without Proxmox Backup Server: jobs,
/// guests no job covers, latest archive per guest, failed backup tasks. Read only,
/// loaded when the screen opens (never on the periodic refresh).
struct ProxmoxBackupsView: View {
    @Environment(ProxmoxStore.self) private var store
    @State private var reports: [UUID: Report] = [:]
    /// A pull to refresh during a load doesn't start a second one.
    @State private var isLoading = false

    enum Report {
        case loading
        case loaded(ProxmoxNativeBackups)
        case failed(String)
    }

    private var services: [ServiceDescriptor] {
        store.services.filter { !store.inventory.duplicateServiceIDs.contains($0.id) }
    }

    var body: some View {
        List {
            ForEach(services) { service in
                serviceSections(service)
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("Backups (Proxmox VE)")
        .navigationBarTitleDisplayMode(.inline)
        .tabBarClearance()
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    @ViewBuilder
    private func serviceSections(_ service: ServiceDescriptor) -> some View {
        switch reports[service.id] ?? .loading {
        case .loading:
            Section {
                ProgressView()
            } header: {
                header(service)
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } header: {
                header(service)
            }
        case .loaded(let report):
            summarySection(report, service: service)
            jobsSection(report)
            if !report.unprotected.isEmpty {
                Section {
                    ForEach(report.unprotected) { guest in
                        Label {
                            Text(verbatim: "\(guest.type == .lxc ? "CT" : "VM") \(guest.vmid) \(guest.name ?? "")")
                        } icon: {
                            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Not covered by any job")
                }
            }
            guestsSection(report)
            if !report.failedTasks.isEmpty {
                Section("Failed backup tasks (24 h)") {
                    ForEach(report.failedTasks) { task in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: task.targetID.map { "vzdump · \($0)" } ?? "vzdump")
                            if case .failed(let message) = task.state {
                                Text(verbatim: message).font(.caption).foregroundStyle(.red)
                            }
                            if let start = task.startTime {
                                Text(start, format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func header(_ service: ServiceDescriptor) -> Text {
        Text(verbatim: service.name)
    }

    private func summarySection(_ report: ProxmoxNativeBackups, service: ServiceDescriptor) -> some View {
        let stale = report.guests.count { report.isStale($0) }
        return Section {
            if stale == 0 {
                Label("Every guest has a backup from the last 2 days", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
            } else {
                Label("\(stale) guests without a backup for 2 days", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            if !report.failedTasks.isEmpty {
                Label("\(report.failedTasks.count) failed backup tasks in the last 24 h", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }
        } header: {
            header(service)
        } footer: {
            if !report.unavailable.isEmpty {
                Text("Some backup information couldn't be read: the token needs the PVEAuditor role on / (Sys.Audit, Datastore.Audit).")
            }
        }
    }

    private func jobsSection(_ report: ProxmoxNativeBackups) -> some View {
        Section("Backup jobs") {
            if report.jobs.isEmpty {
                Text(report.unavailable.contains(.jobs) ? "Couldn't be read." : "No backup job.")
                    .foregroundStyle(.secondary)
            }
            ForEach(report.jobs) { job in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: job.schedule ?? job.id).font(.headline)
                        Spacer()
                        if !job.isEnabled {
                            Text("Disabled").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(verbatim: "\(selectionText(job.selection)) → \(job.storage ?? "?")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if job.isEnabled, let next = job.nextRun {
                        Text("Next run \(next, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func guestsSection(_ report: ProxmoxNativeBackups) -> some View {
        Section {
            ForEach(report.guests) { backup in
                let stale = report.isStale(backup)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(backup.guest.guestType == .lxc ? "CT" : "VM") \(backup.guest.vmid ?? 0) \(backup.guest.displayName)")
                        if let storage = backup.latest?.storage {
                            Text("\(backup.count) archives · \(storage)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let created = backup.latest?.created {
                        Text(created, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(stale ? Color.orange : Color.secondary)
                    } else {
                        Text("No backup").font(.caption).foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Latest backup per guest")
        } footer: {
            Text("Archives found in the storages that hold backups (local, NFS, CIFS, Proxmox Backup Server…). Shown in orange when older than 2 days.")
        }
    }

    private func selectionText(_ selection: ProxmoxBackupJob.Selection) -> String {
        switch selection {
        case .all(let excluded):
            excluded.isEmpty
                ? String(localized: "All guests")
                : String(localized: "All guests except \(excluded.map(String.init).joined(separator: ", "))")
        case .guests(let ids):
            ids.map(String.init).joined(separator: ", ")
        case .pool(let pool):
            String(localized: "Pool \(pool)")
        }
    }

    /// One service after the other; a refused token pauses that service like
    /// every other screen does.
    private func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        for service in services {
            if case .loaded = reports[service.id] {} else { reports[service.id] = .loading }
            guard let client = await store.client(for: service.id) else {
                reports[service.id] = .failed(store.states[service.id]?.message ?? String(localized: "The service is unavailable."))
                continue
            }
            do {
                let report = try await ProxmoxNativeBackups.load(
                    client: client,
                    resources: store.inventory.resources(of: service.id),
                    tasks: store.inventory.tasks(of: service.id)
                )
                reports[service.id] = .loaded(report)
            } catch is CancellationError {
                return
            } catch {
                let state = ServiceLoadState(error: error)
                if state.pausesRequests { store.reportRejectedToken(for: service.id, state: state) }
                reports[service.id] = .failed(state.message ?? String(localized: "The service is unavailable."))
            }
        }
    }
}
