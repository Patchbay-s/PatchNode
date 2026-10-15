import SwiftUI
import UIKit
import PatchNodeCore

/// Settings › Help and support › Guides: network prerequisites, then every
/// service type. Built in, offline, available in demo mode.
struct GuidesListView: View {
    var body: some View {
        List {
            Section {
                guideLink(.networkPrerequisites, systemImage: "network.badge.shield.half.filled")
                guideLink(.ssh, systemImage: "terminal")
            }
            Section("Services") {
                ForEach(ServiceKind.allCases, id: \.self) { kind in
                    guideLink(.service(kind), systemImage: "doc.text")
                }
            }
        }
        .readableWidth()
        .navigationTitle("Guides")
    }

    private func guideLink(_ topic: GuideTopic, systemImage: String) -> some View {
        let guide = GuideLibrary.guide(for: topic)
        return NavigationLink {
            GuideView(topic: topic)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: guide.title.localized)
                    Text(verbatim: guide.summary.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

/// One guide. `focus`: the troubleshooting entry to scroll to (from an error's
/// "What to do?"); `anchor`: an entry without a problem, by its id.
struct GuideView: View {
    let topic: GuideTopic
    var focus: GuideProblem?
    var anchor: String?

    var body: some View {
        let guide = GuideLibrary.guide(for: topic)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(verbatim: guide.summary.localized)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    ForEach(guide.sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(sectionTitle(section.kind, topic: topic))
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                            GuideBlocksView(blocks: section.blocks)
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Troubleshooting")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        ForEach(guide.troubleshooting) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(verbatim: entry.title.localized)
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                GuideBlocksView(blocks: entry.blocks)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                (entry.problem != nil && entry.problem == focus) || entry.id == anchor ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: .rect(cornerRadius: 12)
                            )
                            .id(entry.id)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: ReadableWidth.form, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .task {
                guard let target = focus?.rawValue ?? anchor else { return }
                // After the first layout, so the anchor exists.
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .navigationTitle(Text(verbatim: guide.title.localized))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ kind: GuideSectionKind, topic: GuideTopic) -> LocalizedStringKey {
        if topic == .ssh {
            switch kind {
            case .purpose: return "Why"
            case .setup: return "Setup"
            case .rights: return "Least privilege"
            case .reverseProxy: return "Risks"
            case .verify: return "Revoke the key"
            }
        }
        if topic == .networkPrerequisites {
            switch kind {
            case .purpose: return "Why"
            case .setup: return "Setup"
            case .rights: return "Least privilege"
            case .reverseProxy: return "Reverse proxy and IPS"
            case .verify: return "Verify with curl"
            }
        }
        switch kind {
        case .purpose: return "What it brings to PatchNode"
        case .setup: return "Create the account or token"
        case .rights: return "Minimum rights"
        case .reverseProxy: return "Reverse proxy"
        case .verify: return "Verify with curl"
        }
    }
}

private struct GuideBlocksView: View {
    let blocks: [GuideBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { index in
                block(blocks[index])
            }
        }
    }

    @ViewBuilder
    private func block(_ block: GuideBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(verbatim: text.localized)
                .fixedSize(horizontal: false, vertical: true)
        case .steps(let list):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(list.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(verbatim: list[index].localized)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .bullets(let list):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(list.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•").foregroundStyle(.secondary)
                        Text(verbatim: list[index].localized)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let code):
            CodeBlockView(code: code)
        case .warning(let text):
            Label {
                Text(verbatim: text.localized)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        }
    }
}

/// A command or snippet: monospaced, scrolls sideways, copied in one tap.
struct CodeBlockView: View {
    let code: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            // Commands and generic examples only, never a secret; kept on this
            // device (no Universal Clipboard) like the other copies of the app.
            UIPasteboard.general.setItems(
                [["public.utf8-plain-text": code]],
                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(600)]
            )
            copied = true
            resetTask?.cancel()
            resetTask = Task {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                copied = false
            }
        } label: {
            VStack(alignment: .trailing, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(verbatim: code)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Label(copied ? "Copied" : "Tap to copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: code))
        .accessibilityHint(Text("Copies the command"))
    }
}

extension ServiceLoadState {
    /// The troubleshooting entry for this failure, nil when there's none.
    nonisolated var guideProblem: GuideProblem? {
        switch self {
        case .loading, .loaded: nil
        case .unauthorized: .tokenRejected
        case .forbidden, .insufficientRights: .insufficientRights
        case .blockedByProxy: .proxyBlocked
        case .unreachable, .failed: .unreachable
        }
    }
}

/// "What to do?" next to a failed service: opens its guide at the matching
/// troubleshooting entry.
struct GuideHelpButton: View {
    let kind: ServiceKind
    let state: ServiceLoadState?
    @State private var isPresented = false

    var body: some View {
        if let problem = state?.guideProblem {
            Button("What to do?", systemImage: "questionmark.circle") {
                isPresented = true
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    GuideView(topic: .service(kind), focus: problem)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPresented = false }
                            }
                        }
                }
                // A long text: a page-sized sheet on iPad and Mac.
                .presentationSizing(.page)
            }
        }
    }
}
