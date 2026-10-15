import SwiftUI
import SwiftData
import PatchNodeCore
import ProxmoxKit
import DockerKit
import RemoteAccessKit

/// Add or edit an SSH host: address, user, and an optional link to a Proxmox
/// node, container or VM, or a Docker host (for their shortcuts).
struct SSHHostEditView: View {
    let host: SSHHost?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ProxmoxStore.self) private var proxmoxStore
    @Environment(DockerStore.self) private var dockerStore
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = 22
    @State private var username = ""
    @State private var link: LinkChoice = .none
    @State private var pinnedHostKey = ""
    @State private var forgetsKey = false
    @State private var loaded = false

    /// A link target, as offered by the current inventories.
    struct LinkChoice: Hashable {
        let kind: SSHHostLink
        let serviceID: UUID?
        let target: String

        static let none = LinkChoice(kind: .none, serviceID: nil, target: "")
    }

    private var isValid: Bool {
        SSHEndpoint.isValidHost(hostname.trimmingCharacters(in: .whitespaces))
            && SSHEndpoint.isValidUsername(username.trimmingCharacters(in: .whitespaces))
            && (1...65535).contains(port)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    TextField("Host name or address", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    TextField("User", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("A dedicated user is safer than root: see the SSH guide.")
                }
                Section {
                    Picker("Linked to", selection: $link) {
                        Text("Nothing").tag(LinkChoice.none)
                        ForEach(proxmoxNodes, id: \.self) { choice in
                            Text(verbatim: label(choice)).tag(choice)
                        }
                        ForEach(proxmoxGuests, id: \.self) { choice in
                            Text(verbatim: label(choice)).tag(choice)
                        }
                        ForEach(dockerHosts, id: \.self) { choice in
                            Text(verbatim: label(choice)).tag(choice)
                        }
                        if link != .none, !allChoices.contains(link) {
                            Text("Current link (not loaded)").tag(link)
                        }
                    }
                } footer: {
                    Text("A Proxmox node gets an SSH button and “Enter the container”; a Docker host gets its compose projects.")
                }
                if host != nil {
                    Section {
                        if pinnedHostKey.isEmpty {
                            Text("Not checked yet: shown at the first connection.").foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: pinnedHostKey).font(.footnote.monospaced()).textSelection(.enabled)
                            Button("Forget the host key", systemImage: "key.slash", role: .destructive) { forgetsKey = true }
                        }
                    } header: {
                        Text("Host key")
                    } footer: {
                        Text("Any other key is refused. Forget it only if you reinstalled the server or changed its key on purpose.")
                    }
                }
            }
            .navigationTitle(host == nil ? Text("Add a host") : Text("Edit host"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .confirmationDialog("Forget the host key?", isPresented: $forgetsKey, titleVisibility: .visible) {
                Button("Forget the key of \(hostname)", role: .destructive) { pinnedHostKey = "" }
            } message: {
                Text("The next connection shows the server's fingerprint again, to check before trusting it.")
            }
            .onAppear(perform: load)
        }
        .privacyCover()
    }

    private var proxmoxNodes: [LinkChoice] {
        store(proxmoxStore.inventory.nodes.compactMap { item in
            item.resource.node.map { LinkChoice(kind: .proxmoxNode, serviceID: item.serviceID, target: $0) }
        })
    }

    private var proxmoxGuests: [LinkChoice] {
        store(proxmoxStore.inventory.guests.compactMap { item in
            item.resource.vmid.map { LinkChoice(kind: .proxmoxGuest, serviceID: item.serviceID, target: String($0)) }
        })
    }

    private var dockerHosts: [LinkChoice] {
        store(dockerStore.inventory.hosts.map { LinkChoice(kind: .dockerHost, serviceID: $0.serviceID, target: $0.host.id) })
    }

    private var allChoices: [LinkChoice] { proxmoxNodes + proxmoxGuests + dockerHosts }

    private func store(_ choices: [LinkChoice]) -> [LinkChoice] {
        var seen = Set<LinkChoice>()
        return choices.filter { seen.insert($0).inserted }
    }

    private func label(_ choice: LinkChoice) -> String {
        switch choice.kind {
        case .proxmoxNode:
            return String(localized: "Proxmox node \(choice.target)")
        case .proxmoxGuest:
            let name = proxmoxStore.inventory.guests.first { $0.serviceID == choice.serviceID && $0.resource.vmid.map(String.init) == choice.target }?.resource.displayName ?? choice.target
            return String(localized: "Container or VM \(name)")
        case .dockerHost:
            let name = dockerStore.inventory.hosts.first { $0.serviceID == choice.serviceID && $0.host.id == choice.target }?.host.name ?? choice.target
            return String(localized: "Docker host \(name)")
        case .none:
            return ""
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let host else { return }
        name = host.name
        hostname = host.hostname
        port = host.port
        username = host.username
        pinnedHostKey = host.pinnedHostKey
        link = LinkChoice(kind: host.link, serviceID: host.linkedServiceID, target: host.linkedTarget)
    }

    private func save() {
        let target = host ?? SSHHost(name: "", hostname: "", username: "")
        let trimmedHost = hostname.trimmingCharacters(in: .whitespaces)
        // Another address, another server: its key must be checked again.
        if let host, host.hostname != trimmedHost || host.port != port { pinnedHostKey = "" }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.hostname = trimmedHost
        target.port = port
        target.username = username.trimmingCharacters(in: .whitespaces)
        target.link = link.kind
        target.linkedServiceID = link.serviceID
        target.linkedTarget = link.target
        target.pinnedHostKey = pinnedHostKey
        if host == nil { modelContext.insert(target) }
        try? modelContext.save()
        dismiss()
    }
}

/// SSH hosts linked to a target, for the shortcuts.
enum SSHHostLookup {
    static func host(in hosts: [SSHHost], link: SSHHostLink, serviceID: UUID, target: String) -> SSHHost? {
        hosts.first { $0.link == link && $0.linkedServiceID == serviceID && $0.linkedTarget == target }
    }
}
