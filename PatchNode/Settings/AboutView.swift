import SwiftUI

/// Settings > About: version, privacy policy, support, introduction.
struct AboutView: View {
    @State private var showsIntroduction = false

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: Self.version)
            }
            Section {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
                if let url = AppLinks.privacyPolicy {
                    Link(destination: url) {
                        Label("Privacy policy on the web", systemImage: "safari")
                    }
                }
                if let url = AppLinks.support {
                    Link(destination: url) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                }
            }
            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Licenses", systemImage: "doc.plaintext")
                }
            }
            Section {
                Button("Show the introduction", systemImage: "sparkles") {
                    showsIntroduction = true
                }
            }
        }
        .readableWidth()
        .navigationTitle("About")
        .sheet(isPresented: $showsIntroduction) {
            OnboardingView()
        }
    }

    /// "1.0 (3)": marketing version and build.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

/// The privacy policy, readable offline. Same content as docs/appstore/privacy-policy.md.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PatchNode collects no data. There is no account, no analytics, no advertising and no tracking, and the developer receives nothing.")
                Text("What you configure stays on this iPhone: service names and addresses in the app's private storage (included in this iPhone's backups), tokens and passwords in the Keychain, for this device only.")
                Text("iCloud sync is off by default. Turned on (Settings › iCloud), your configuration goes to your own iCloud, without tokens; tokens go to iCloud Keychain, end-to-end encrypted, only with their own separate option. The developer has no access to either.")
                Text("The app connects only to the servers you add, and to api.tailscale.com if you add Tailscale. The demo contacts no server at all.")
                Text("SSH and consoles (off until you use them): the app connects directly to your own servers. The SSH key is created on the device and its private part never leaves the Keychain; an SSH password is never stored. What you type or see in a terminal or console, and the compose and .env files you edit, is never stored or logged. The graphical console is built into the app.")
                Text("Widgets and Siri read a summary kept on this iPhone, without any address or secret.")
                Text("Notifications, if you turn them on, are posted by the iPhone itself, with a count only: no server, no name, no address.")
                Text("Crash and performance reports from iOS stay on this iPhone; they leave it only if you share one or attach a crash summary to a support e-mail.")
                Text("Deleting a service removes its token from the Keychain. Delete your services before deleting the app: iOS can keep Keychain items after an app is removed.")
                Text("Contacting support opens your Mail app with a prefilled message; nothing is sent until you send it. An optional diagnostic report, off by default and shown in full first, contains only versions, device model, language, service types and error codes: never an address, name or token.")
            }
            .padding()
            .frame(maxWidth: ReadableWidth.form, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
