import SwiftUI
import PatchNodeCore

/// Settings › Help and support: guides, short FAQ, contact.
struct HelpSupportView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    GuidesListView()
                } label: {
                    Label("Guides", systemImage: "book")
                }
                NavigationLink {
                    FAQView()
                } label: {
                    Label("FAQ", systemImage: "questionmark.bubble")
                }
            } footer: {
                Text("Step-by-step setup for every service type and the network prerequisites, available offline.")
            }
            Section {
                NavigationLink {
                    SupportView()
                } label: {
                    Label("Contact support", systemImage: "envelope")
                }
            } footer: {
                Text("The support address isn't set in this version yet.")
            }
        }
        .readableWidth()
        .navigationTitle("Help and support")
    }
}

/// Short answers to the questions asked most.
struct FAQView: View {
    private let entries: [(question: LocalizedStringKey, answer: LocalizedStringKey)] = [
        ("Why does it work at home but not outside?",
         "PatchNode talks directly to your servers. Outside, your iPhone needs a VPN such as Tailscale or WireGuard, and your names must resolve through it (split DNS). See Guides › Network prerequisites."),
        ("Why is HTTPS required?",
         "Your tokens travel with every request. PatchNode accepts only HTTPS with a valid certificate: put your services behind a reverse proxy with, for example, a Let's Encrypt certificate."),
        ("A service says “paused”. Why?",
         "After a refused token or a reverse proxy block, PatchNode stops asking so it never gets your IP banned by CrowdSec or fail2ban. A proxy block resumes by itself; a refused token waits for you to pull to refresh."),
        ("Where are my tokens stored?",
         "In this iPhone's Keychain, for this device only, unless you turn on Settings › iCloud › Also sync tokens with iCloud Keychain (off by default). They are sent only to the service they belong to."),
        ("I lost my iPhone, or a token may have leaked. What should I do?",
         "Revoke the tokens on each server (Proxmox: Datacenter › Permissions › API Tokens; Home Assistant: your profile › Security; Portainer, Tailscale, AdGuard: their access-token settings), then create new ones. PatchNode is locked by Face ID or your passcode, but a revoked token is the only certain protection. Prefer read-only tokens: a Portainer or Home Assistant token can control everything its user can."),
        ("Do you receive any data?",
         "No. PatchNode has no account, analytics, or server. It connects only to the servers you configure; nothing is shared with us unless you choose to share it."),
        ("Why are the widgets late?",
         "Widgets show the latest data the app saved. iOS decides when background refresh runs; opening the app refreshes them."),
        ("Can I try without a server?",
         "Yes: Settings › Demo shows a complete sample HomeLab generated on the iPhone."),
    ]

    var body: some View {
        List {
            ForEach(entries.indices, id: \.self) { index in
                DisclosureGroup {
                    Text(entries[index].answer)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text(entries[index].question)
                }
            }
        }
        .readableWidth()
        .navigationTitle("FAQ")
    }
}
