import SwiftUI
import SwiftData
import PatchNodeCore
import RemoteAccessKit

/// Settings › SSH: off by default. This device's key (public half only), the
/// line to put in authorized_keys, and the hosts.
struct SSHSettingsView: View {
    @AppStorage(SSHSettings.enabledKey) private var enabled = false
    @AppStorage(DemoMode.key) private var demoMode = false
    @Query(sort: \SSHHost.name) private var hosts: [SSHHost]
    @Environment(\.modelContext) private var modelContext
    @Environment(SSHLauncher.self) private var launcher
    @Environment(AppLockController.self) private var lockController
    @State private var key: SSHDeviceKey?
    @State private var keyError = false
    @State private var editing: SSHHost?
    @State private var adding = false
    @State private var hostToDelete: SSHHost?
    @State private var confirmsNewKey = false
    @State private var showsGuide = false

    var body: some View {
        List {
            Section {
                Toggle("SSH terminal", systemImage: "terminal", isOn: Binding(get: { enabled }, set: setEnabled))
            } footer: {
                Text("Open a terminal on your own servers over SSH, with a key generated on this device. Off by default. PatchNode connects only to the hosts you add.")
            }
            if enabled {
                keySection
                hostsSection
            }
            Section {
                Button("SSH guide", systemImage: "book") { showsGuide = true }
            } footer: {
                Text("A dedicated user, the docker group or sudo, the risks, and how to revoke the key.")
            }
        }
        .readableWidth()
        .navigationTitle(Text(verbatim: "SSH"))
        .task(id: enabled) { if enabled { await loadKey() } }
        .sheet(isPresented: $adding) { SSHHostEditView(host: nil) }
        .sheet(item: $editing) { host in SSHHostEditView(host: host) }
        .sheet(isPresented: $showsGuide) {
            NavigationStack {
                SSHGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showsGuide = false } }
                    }
            }
            .presentationSizing(.page)
        }
        .confirmationDialog(
            Text("Delete \(hostToDelete?.name ?? "")?"),
            isPresented: Binding(get: { hostToDelete != nil }, set: { if !$0 { hostToDelete = nil } }),
            titleVisibility: .visible,
            presenting: hostToDelete
        ) { host in
            Button("Delete \(host.name)", role: .destructive) { delete(host) }
        } message: { _ in
            Text("Its pinned host key is forgotten too. The key stays in the server's authorized_keys until you remove it there.")
        }
        .confirmationDialog(
            "Replace this device's SSH key?",
            isPresented: $confirmsNewKey,
            titleVisibility: .visible
        ) {
            Button("Replace the key", role: .destructive) { Task { await replaceKey() } }
        } message: {
            Text("The current key is deleted from this device: every server must receive the new public key. Remove the old line from their authorized_keys.")
        }
    }

    @ViewBuilder
    private var keySection: some View {
        Section {
            if let key {
                NavigationLink {
                    SSHPublicKeyView(key: key)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("This device's public key", systemImage: "key")
                        Text(verbatim: key.fingerprint)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Button("Replace the key", systemImage: "arrow.triangle.2.circlepath", role: .destructive) { confirmsNewKey = true }
            } else if keyError {
                Text("The key couldn't be read from the Keychain.").foregroundStyle(.red)
            } else {
                ProgressView()
            }
        } header: {
            Text("Key")
        } footer: {
            Text("ed25519, created on this device. The private key stays in this device's Keychain: never synced, never exported. Only the public key is shown.")
        }
    }

    @ViewBuilder
    private var hostsSection: some View {
        Section {
            if demoMode {
                Text("Your SSH hosts are hidden during the demo.").foregroundStyle(.secondary)
            } else {
                ForEach(hosts.uniqued(by: \.id)) { host in
                    HStack {
                        Button {
                            Task { await launcher.connect(SSHHostSnapshot(host)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: host.name.isEmpty ? host.hostname : host.name)
                                Text(verbatim: "\(host.username)@\(host.hostname)\(host.port == 22 ? "" : ":\(host.port)")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                        Spacer()
                        if launcher.launching.contains(host.id) { ProgressView() }
                        Button("Edit", systemImage: "info.circle") { editing = host }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { hostToDelete = host }
                    }
                }
                Button("Add a host", systemImage: "plus") { adding = true }
            }
        } header: {
            Text("Hosts")
        } footer: {
            Text("Tap a host to connect. Face ID is asked for every session; the first connection shows the server's fingerprint to check.")
        }
    }

    private func setEnabled(_ on: Bool) {
        guard on else {
            enabled = false
            return
        }
        Task {
            if await lockController.authenticateForAction(reason: String(localized: "Turn on the SSH terminal")) {
                enabled = true
            }
        }
    }

    private func loadKey() async {
        do {
            key = try await SSHDeviceKey.loadOrCreate(in: SSHDeviceKey.keychain())
            keyError = false
        } catch {
            keyError = true
        }
    }

    private func replaceKey() async {
        guard await lockController.authenticateForAction(reason: String(localized: "Replace this device's SSH key"), alwaysAsk: true) else { return }
        do {
            try await SSHDeviceKey.delete(from: SSHDeviceKey.keychain())
        } catch {
            keyError = true
            return
        }
        key = nil
        await loadKey()
    }

    private func delete(_ host: SSHHost) {
        let id = host.id
        let copies = (try? modelContext.fetch(FetchDescriptor<SSHHost>(predicate: #Predicate { $0.id == id }))) ?? [host]
        copies.forEach(modelContext.delete)
        try? modelContext.save()
    }
}

/// The public key, and the line to add to `~/.ssh/authorized_keys`, with
/// optional restrictions.
struct SSHPublicKeyView: View {
    let key: SSHDeviceKey
    @State private var sources = ""
    @State private var restricted = true
    @State private var copied: String?

    private var publicKey: String {
        key.openSSHPublicKey(comment: "PatchNode-\(UIDevice.current.model)-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.omitted)))")
    }

    private var line: String? {
        try? AuthorizedKeysLine.make(publicKey: publicKey, from: sources, restricted: restricted)
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: publicKey)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                copyButton("Copy the public key", publicKey)
                ShareLink(item: publicKey) { Label("Share the public key", systemImage: "square.and.arrow.up") }
            } header: {
                Text("Public key")
            } footer: {
                Text("Fingerprint: \(key.fingerprint)")
            }
            Section {
                Toggle("No forwarding (recommended)", isOn: $restricted)
                TextField("Allowed sources (optional), e.g. 100.64.0.0/10", text: $sources)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                if let line {
                    Text(verbatim: line)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    copyButton("Copy the line", line)
                } else {
                    Text("Addresses or ranges only, separated by commas.").foregroundStyle(.red)
                }
            } header: {
                Text("authorized_keys line")
            } footer: {
                Text("Add this line to ~/.ssh/authorized_keys of the user PatchNode connects as. from= limits the addresses the key is accepted from (your VPN's range); the options forbid port, agent and X11 forwarding.")
            }
        }
        .readableWidth()
        .navigationTitle("Public key")
    }

    private func copyButton(_ title: LocalizedStringKey, _ value: String) -> some View {
        Button(copied == value ? "Copied" : title, systemImage: copied == value ? "checkmark" : "doc.on.doc") {
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true])
            copied = value
        }
    }
}

/// The built-in SSH guide.
struct SSHGuideView: View {
    var body: some View {
        GuideView(topic: .ssh)
    }
}
