import SwiftUI
import UIKit
import PatchNodeCore

/// Shown instead of the app when its store couldn't open (M-R2: no more
/// `fatalError`). Nothing is deleted: an update can still open the store. Shows
/// no configuration, so it needs no unlock. The e-mail to support carries the
/// versions and the error code only, and is sent by the user's Mail app.
struct StoreErrorView: View {
    let code: String
    let offersDemo: Bool
    let onDemo: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var showsCopiedAddress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Your configuration couldn't be opened")
                        .font(.title2.bold())
                    Text("PatchNode couldn't open the file that holds your services. Nothing was deleted: an update of the app may be able to open it again. Your tokens are still in the Keychain.")
                    Text("Try quitting PatchNode from the app switcher and opening it again. If this screen comes back, contact support and check the App Store for an update.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Error code") {
                        Text(verbatim: code).font(.footnote.monospaced())
                    }
                    if let mail = supportURL {
                        Button("Contact support", systemImage: "envelope") { contact(mail) }
                            .buttonStyle(.borderedProminent)
                    }
                    if offersDemo {
                        Button("Try the demo", systemImage: "sparkles.rectangle.stack", action: onDemo)
                            .buttonStyle(.bordered)
                        Text("The demo uses sample data generated on this iPhone and doesn't touch your configuration.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: ReadableWidth.form, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text(verbatim: "PatchNode"))
            .navigationBarTitleDisplayMode(.inline)
            .alert("Address copied", isPresented: $showsCopiedAddress) {
                if MacWindow.isMac, let mail = supportURL {
                    Button("Open the mail app") { openURL(mail) }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("The support address was copied. Paste it in your mail app, with your message.")
            }
        }
    }

    /// The mail app, or the address copied when no app takes the link (and
    /// always on the Mac, where Mail is often not set up).
    private func contact(_ mail: URL) {
        guard !MacWindow.isMac else { return copyAddress() }
        openURL(mail) { accepted in
            if !accepted { copyAddress() }
        }
    }

    private func copyAddress() {
        guard let address = AppLinks.supportEmail else { return }
        UIPasteboard.general.string = address
        showsCopiedAddress = true
    }

    /// Versions and the error code: no address, name or token (the store
    /// couldn't even be read).
    private var supportURL: URL? {
        guard let address = AppLinks.supportEmail else { return nil }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let body = """


        ---
        Store error: \(code)
        PatchNode \(version) (\(build)), iOS \(UIDevice.current.systemVersion)
        """
        return SupportMessage.mailtoURL(to: address, subject: SupportMessage.subject(category: .bug, kind: nil), body: body)
    }
}
