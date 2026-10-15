import SwiftUI
import PatchNodeCore
import ProxmoxKit

/// Disk health of the Proxmox VE nodes, per service and its mode
/// (`SMARTSetting`). Opening the screen sends no request: it shows the last
/// wanted read (disks with SMART, ZFS pools) and its date. The disks are read
/// only through `AppModel.readSMART` (`DiskHealthAccess`): the button, or once
/// a day in automatic mode, because smartctl wakes disks in standby. Off: no
/// request at all and nothing kept.
struct ProxmoxDisksView: View {
    @Environment(AppModel.self) private var model
    @Environment(ProxmoxStore.self) private var store
    /// The last read's error, until the next read.
    @State private var errors: [UUID: String] = [:]
    @State private var confirmsSMART: ServiceDescriptor?

    private var services: [ServiceDescriptor] {
        store.services.filter { !store.inventory.duplicateServiceIDs.contains($0.id) }
    }

    var body: some View {
        List {
            ForEach(services) { service in
                smartSection(service)
                if model.smartSetting(for: service.id).mode != .disabled {
                    readingSections(service)
                }
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("Disk health")
        .navigationBarTitleDisplayMode(.inline)
        .tabBarClearance()
        .confirmationDialog(
            Text("Read the SMART status of “\(confirmsSMART?.name ?? "")”?"),
            isPresented: Binding(get: { confirmsSMART != nil }, set: { if !$0 { confirmsSMART = nil } }),
            titleVisibility: .visible,
            presenting: confirmsSMART
        ) { service in
            Button("Read SMART status") {
                confirmsSMART = nil
                Task { await readSMART(service) }
            }
        } message: { _ in
            Text("Proxmox runs smartctl on every disk of the nodes: it may wake disks in standby.")
        }
    }

    private func modeBinding(_ id: UUID) -> Binding<SMARTSetting.Mode> {
        Binding(get: { model.smartSetting(for: id).mode }, set: { mode in update(id) { $0.mode = mode } })
    }

    private func timeBinding(_ id: UUID) -> Binding<Date> {
        Binding(
            get: {
                let setting = model.smartSetting(for: id)
                return Calendar.current.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                update(id) { $0.hour = parts.hour ?? SMARTSetting.defaultHour; $0.minute = parts.minute ?? SMARTSetting.defaultMinute }
            }
        )
    }

    private func update(_ id: UUID, _ change: (inout SMARTSetting) -> Void) {
        var value = model.smartSetting(for: id)
        change(&value)
        if value.mode == .disabled { errors[id] = nil }
        model.setSMARTSetting(value, for: id)
    }

    /// The mode of the service, its last read and the button.
    private func smartSection(_ service: ServiceDescriptor) -> some View {
        let current = model.smartSetting(for: service.id)
        // Observed: shown again after any read (button or automatic).
        _ = model.smartReadRevision
        let lastRead = SMARTReadingStore.shared.lastRead(for: service.id)
        let reading = model.smartReadsInFlight.contains(service.id)
        return Section {
            Picker("SMART disk health", selection: modeBinding(service.id)) {
                Text("Off").tag(SMARTSetting.Mode.disabled)
                Text("On demand").tag(SMARTSetting.Mode.onDemand)
                Text("Automatic, daily").tag(SMARTSetting.Mode.automatic)
            }
            switch current.mode {
            case .disabled:
                Label("Disk health off", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            case .onDemand, .automatic:
                if current.mode == .automatic {
                    DatePicker("Time", selection: timeBinding(service.id), displayedComponents: .hourAndMinute)
                }
                LabeledContent("Last SMART read") {
                    if let lastRead {
                        Text(lastRead, format: .dateTime.day().month().hour().minute())
                    } else {
                        Text("Not read")
                    }
                }
                Button("Read SMART status", systemImage: "stethoscope") { confirmsSMART = service }
                    .disabled(reading)
                if reading { ProgressView() }
            }
        } header: {
            Text(verbatim: service.name)
        } footer: {
            switch current.mode {
            case .disabled:
                Text("PatchNode never reads the disks of this service: no disk list, no SMART, no ZFS pools, and no disk notification.")
            case .onDemand:
                Text("The disks are read only with the button: disk list with SMART, then ZFS pools. Reading SMART may wake disks in standby. Disk notifications come from the last read.")
            case .automatic:
                Text("Once a day from this time, the disks are read like with the button. iOS chooses the exact moment in the background; the read happens at the latest the first time you open PatchNode after this time. Choose a time when the disks already spin (a scheduled backup, for example): reading SMART may wake disks in standby.")
            }
        }
    }

    /// The last read, kept: nothing is requested here.
    @ViewBuilder
    private func readingSections(_ service: ServiceDescriptor) -> some View {
        let _ = model.smartReadRevision
        if let message = errors[service.id] {
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        if let report = SMARTReadingStore.shared.reading(for: service.id)?.report {
            if report.nodes.isEmpty {
                Section {
                    Text("No online node.").foregroundStyle(.secondary)
                }
            }
            ForEach(report.nodes) { node in
                nodeSection(node, service: service)
            }
        }
    }

    private func nodeSection(_ node: ProxmoxDiskHealth.Node, service: ServiceDescriptor) -> some View {
        Section {
            ForEach(node.pools) { pool in
                PoolRow(pool: pool)
            }
            if node.unavailable.contains(.zfs) {
                Text("ZFS pools couldn't be read.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(node.disks) { disk in
                DiskRow(disk: disk)
            }
            if node.unavailable.contains(.disks) {
                Text("Disks couldn't be read.").font(.caption).foregroundStyle(.secondary)
            } else if node.disks.isEmpty {
                Text("No disk reported.").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(verbatim: services.count > 1 ? "\(service.name) · \(node.name)" : node.name)
        } footer: {
            if !node.unavailable.isEmpty {
                Text("The token needs the PVEAuditor role on / (Sys.Audit) to read disks and ZFS pools.")
            }
        }
    }
}

extension ProxmoxDisksView {
    /// "Read SMART status": confirmed, then the complete read.
    fileprivate func readSMART(_ service: ServiceDescriptor) async {
        // Before the first refresh (cold launch), the nodes aren't known yet.
        let loaded = !store.inventory.resources(of: service.id).isEmpty
        let message: String?
        do {
            try await model.readSMART(of: service.id, at: .userRequest)
            message = loaded ? nil : String(localized: "PatchNode is still loading this service: try again in a moment.")
        } catch {
            message = ServiceLoadState(error: error).message ?? String(localized: "The service is unavailable.")
        }
        // Turned off meanwhile: nothing to show.
        errors[service.id] = model.smartSetting(for: service.id).mode == .disabled ? nil : message
        SMARTBackgroundRead.schedule(notBefore: model.smartRetryNotBefore)
    }
}

private func levelColor(_ level: HealthLevel) -> Color {
    switch level {
    case .ok: .green
    case .warning: .orange
    case .critical: .red
    }
}

private struct PoolRow: View {
    let pool: ProxmoxZFSPool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "cylinder.split.1x2")
                .foregroundStyle(levelColor(pool.level))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pool.name).font(.headline)
                if let usage = pool.usage, let size = pool.size {
                    Text("\(usage.formatted(.percent.precision(.fractionLength(0)))) of \(size.formatted(.byteCount(style: .file))) used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(verbatim: pool.health)
                .font(.caption.bold())
                .foregroundStyle(pool.health == "ONLINE" ? Color.secondary : levelColor(pool.level))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("ZFS pool \(pool.name), \(pool.health)"))
    }
}

private struct DiskRow: View {
    let disk: ProxmoxDisk

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: disk.type == "hdd" ? "internaldrive" : "memorychip")
                .foregroundStyle(levelColor(disk.level))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: disk.model ?? disk.devpath)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lifeLeft = disk.lifeLeft {
                    Text("\(lifeLeft) % life left")
                        .font(.caption)
                        .foregroundStyle(disk.level == .warning ? Color.orange : Color.secondary)
                }
            }
            Spacer()
            healthText
                .font(.caption.bold())
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [disk.devpath]
        if let size = disk.size { parts.append(size.formatted(.byteCount(style: .file))) }
        if let usage = disk.usage, !usage.isEmpty { parts.append(usage) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var healthText: some View {
        switch disk.health {
        case .passed: Text("SMART OK").foregroundStyle(.secondary)
        case .failed: Text("SMART failed").foregroundStyle(.red)
        case .unknown: Text("No SMART data").foregroundStyle(.secondary)
        }
    }
}
