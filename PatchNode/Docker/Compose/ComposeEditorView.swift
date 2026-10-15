import SwiftUI
import RemoteAccessKit

/// A compose file or `.env`: loaded over SSH or from Portainer, edited with
/// line numbers, the changes shown before saving (validated, backed up).
/// `.env` values stay masked until asked.
struct ComposeEditorView: View {
    let file: ComposeFile
    let controller: ComposeController
    @State private var original: String?
    @State private var text = ""
    @State private var existed = true
    @State private var loadError: String?
    @State private var revealsValues = false
    @State private var showsDiff = false
    @State private var saving = false
    @State private var invalidOutput: String?

    private var hasChanges: Bool {
        original.map { $0 != text } ?? false
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't open the file", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: loadError)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if original == nil {
                ProgressView()
            } else if file.isEnv && !revealsValues {
                List {
                    Section {
                        let masked = EnvMasking.masked(text)
                        Text(verbatim: masked.isEmpty ? " " : masked)
                            .font(.footnote.monospaced())
                    } footer: {
                        Text(existed ? "Values are hidden." : "This project has no .env yet: saving creates it.")
                    }
                    Section {
                        Button("Show and edit the values", systemImage: "eye") {
                            Task { revealsValues = await controller.authorizeReveal(file) }
                        }
                    }
                }
            } else {
                CodeTextView(text: $text)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .navigationTitle(Text(verbatim: file.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { showsDiff = true }
                    .disabled(!hasChanges || saving)
            }
        }
        .task { if original == nil { await load() } }
        .sheet(isPresented: $showsDiff) {
            ComposeDiffSheet(
                file: file, old: original ?? "", new: text, masksValues: file.isEnv && !revealsValues, saving: saving
            ) {
                showsDiff = false
                Task { await save() }
            }
        }
        .alert("Not saved", isPresented: Binding(get: { invalidOutput != nil }, set: { if !$0 { invalidOutput = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The configuration was refused; the file on the server is unchanged.\n\n\(invalidOutput ?? "")")
        }
        .privacySensitive()
    }

    private func load() async {
        loadError = nil
        guard let backend = await controller.connect() else {
            loadError = controller.errorMessage ?? String(localized: "Connection lost.")
            controller.errorMessage = nil
            return
        }
        do {
            let content = try await backend.read(file)
            existed = content != nil
            original = content ?? ""
            text = content ?? ""
        } catch {
            loadError = ComposeController.message(for: error)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        switch await controller.save(file, content: text, existed: existed) {
        case .saved?:
            original = text
            existed = true
        case .invalid(let output)?:
            invalidOutput = output
        case nil:
            break
        }
    }
}

/// What changes, before saving.
struct ComposeDiffSheet: View {
    /// Beyond this many lines, a summary instead of the line-by-line diff.
    static let maxDiffLines = 5000

    let file: ComposeFile
    let old: String
    let new: String
    let masksValues: Bool
    let saving: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Computed once, off the main actor.
    @State private var lines: [TextDiff.Line]?
    @State private var tooLong = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if tooLong {
                        Text("The file is too long to show its changes line by line.").foregroundStyle(.secondary)
                    } else if lines == nil {
                        ProgressView()
                    }
                    ForEach(lines ?? []) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: symbol(line.kind)).foregroundStyle(color(line.kind))
                            Text(verbatim: "\(line.number)").foregroundStyle(.secondary).frame(minWidth: 28, alignment: .trailing)
                            Text(verbatim: masksValues ? EnvMasking.masked(line.text) : line.text)
                                .foregroundStyle(line.kind == .unchanged ? Color.secondary : Color.primary)
                        }
                        .font(.caption.monospaced())
                        .listRowBackground(background(line.kind))
                    }
                } footer: {
                    Text("Saving validates the project with docker compose config first, then keeps the previous version as a timestamped .bak file (the 5 latest are kept).")
                }
            }
            .task {
                guard lines == nil, !tooLong else { return }
                let (old, new) = (old, new)
                if old.count(where: { $0 == "\n" }) + new.count(where: { $0 == "\n" }) > Self.maxDiffLines {
                    tooLong = true
                    return
                }
                lines = await Task.detached(priority: .userInitiated) { TextDiff.lines(old: old, new: new) }.value
            }
            .navigationTitle(Text("Changes to \(file.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave).disabled(saving)
                }
            }
        }
        .privacyCover()
    }

    private func symbol(_ kind: TextDiff.Line.Kind) -> String {
        switch kind { case .added: "+"; case .removed: "−"; case .unchanged: " " }
    }

    private func color(_ kind: TextDiff.Line.Kind) -> Color {
        switch kind { case .added: .green; case .removed: .red; case .unchanged: .secondary }
    }

    private func background(_ kind: TextDiff.Line.Kind) -> Color? {
        switch kind {
        case .added: Color.green.opacity(0.12)
        case .removed: Color.red.opacity(0.12)
        case .unchanged: nil
        }
    }
}
