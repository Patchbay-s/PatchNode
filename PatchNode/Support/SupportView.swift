import SwiftUI
import UIKit
import MessageUI
import PatchNodeCore

/// Settings › Help and support › Contact support. An optional diagnostic report
/// is off by default and shown in full before the user chooses how to share it.
struct SupportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var category: SupportMessage.Category = .setupHelp
    @State private var kind: ServiceKind?
    @State private var details = ""
    @State private var attachReport = false
    /// Frozen when the switch is turned on: what's previewed is what's sent.
    @State private var report: SupportReport?
    /// Age of the errors in the report counted from this moment, in the preview
    /// and in the e-mail alike.
    @State private var reportDate = Date.now
    @State private var attachCrashes = false
    /// Frozen when the switch is turned on, like the report.
    @State private var crashSummary: String?
    @State private var showsMail = false
    @State private var showsCopiedAddress = false

    var body: some View {
        Form {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(SupportMessage.Category.allCases) { category in
                        Text(Self.title(category)).tag(category)
                    }
                }
                Picker("Service type", selection: $kind) {
                    Text("General").tag(ServiceKind?.none)
                    ForEach(ServiceKind.allCases, id: \.self) { kind in
                        Text(verbatim: kind.displayName).tag(ServiceKind?.some(kind))
                    }
                }
            }
            Section {
                TextEditor(text: $details)
                    .frame(minHeight: 140)
                    .accessibilityLabel(Text("Description"))
            } header: {
                Text("Description")
            } footer: {
                Text("Describe what you did and what you saw. Never paste a token, a password or an address.")
            }
            Section {
                Toggle("Attach a diagnostic report", isOn: $attachReport)
                if let report {
                    Text(verbatim: report.text(now: reportDate))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } footer: {
                Text("App and iOS versions, device model, language, types of services configured, demo mode, and the kind and HTTP code of the latest errors per service type. Never a URL, host name, address, service name, token or content. The full text is shown above before sending.")
            }
            Section {
                Toggle("Attach a summary of crashes", isOn: $attachCrashes)
                if let crashSummary {
                    Text(verbatim: crashSummary)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Crashes and hangs iOS reported in the last 30 days: date, versions and exception type only. Never a URL, host name, address, service name, token or call stack. The full text is shown above before sending.")
            }
            Section {
                Button("Send by e-mail", systemImage: "envelope") { send() }
                    .disabled(AppLinks.supportEmail == nil || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (attachCrashes && crashSummary == nil))
                if AppLinks.supportEmail == nil, let support = AppLinks.support {
                    Link(destination: support) {
                        Label("Help and support", systemImage: "questionmark.circle")
                    }
                }
                if let whatsApp = AppLinks.whatsAppURL {
                    Link(destination: whatsApp) {
                        Label("WhatsApp", systemImage: "message")
                    }
                }
            } footer: {
                if AppLinks.supportEmail == nil {
                    Text("The support address isn't set in this version yet.")
                } else {
                    Text("Your Mail app opens with the message ready; nothing is sent until you send it.")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Contact support")
        .onChange(of: attachReport) { _, attach in
            reportDate = .now
            report = attach ? makeReport() : nil
        }
        .onChange(of: attachCrashes) { _, attach in
            crashSummary = nil
            guard attach else { return }
            // Service names and hosts are scrubbed again from iOS's text.
            let forbidden = model.stores.flatMap { $0.services }.flatMap { [$0.name, $0.url.host() ?? ""] }
            Task {
                let reports = await SystemReportArchive.shared.reports()
                if attachCrashes { crashSummary = SystemReportText.supportSummary(reports, forbidden: forbidden) }
            }
        }
        .sheet(isPresented: $showsMail) {
            if let address = AppLinks.supportEmail {
                MailComposeView(recipient: address, subject: subject, body: messageBody) {
                    showsMail = false
                }
                .ignoresSafeArea()
            }
        }
        .alert("Address copied", isPresented: $showsCopiedAddress) {
            if MacWindow.isMac, let address = AppLinks.supportEmail,
               let url = SupportMessage.mailtoURL(to: address, subject: subject, body: messageBody) {
                Button("Open the mail app") { openURL(url) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("The support address was copied. Paste it in your mail app, with your message.")
        }
    }

    private var subject: String {
        SupportMessage.subject(category: category, kind: kind)
    }

    private var messageBody: String {
        SupportMessage.body(description: details, report: attachReport ? report : nil,
                            crashSummary: attachCrashes ? crashSummary : nil, now: reportDate)
    }

    /// Mail if set up, otherwise a mailto: link, otherwise the address copied.
    /// On the Mac, where Mail is often not set up (a mailto: link would open its
    /// account setup), the address is copied and the alert offers the link.
    private func send() {
        guard let address = AppLinks.supportEmail else { return }
        if MFMailComposeViewController.canSendMail() {
            showsMail = true
            return
        }
        if MacWindow.isMac {
            copy(address)
            return
        }
        guard let url = SupportMessage.mailtoURL(to: address, subject: subject, body: messageBody) else {
            copy(address)
            return
        }
        openURL(url) { accepted in
            if !accepted { copy(address) }
        }
    }

    private func copy(_ address: String) {
        UIPasteboard.general.string = address
        showsCopiedAddress = true
    }

    private func makeReport() -> SupportReport {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        return SupportReport(
            appVersion: version,
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: Self.deviceModel,
            language: Locale.preferredLanguages.first ?? "?",
            services: model.stores.flatMap { store in store.services.map { (id: $0.id, kind: $0.kind) } },
            demoMode: DemoMode.isOn,
            log: RequestLog.shared.entries()
        )
    }

    /// Hardware identifier such as "iPhone18,1": the model, not the device.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func title(_ category: SupportMessage.Category) -> LocalizedStringKey {
        switch category {
        case .bug: "Bug"
        case .setupHelp: "Setup help"
        case .suggestion: "Suggestion"
        }
    }
}

/// The system mail composer, prefilled. The user reviews and sends it.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func mailComposeController(
            _ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?
        ) {
            // The sheet is dismissed by SwiftUI when its binding turns false.
            Task { @MainActor in self.onFinish() }
        }
    }
}
