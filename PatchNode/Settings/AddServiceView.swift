import SwiftUI
import PatchNodeCore
import ProxmoxKit
import DockerKit

struct AddServiceView: View {
    @Bindable var viewModel: AddServiceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if viewModel.isEditing {
                        // The type of a configured service never changes.
                        LabeledContent("Service type") {
                            Text(verbatim: viewModel.kind.displayName)
                        }
                    } else {
                        // A menu grouped by category: the inline list of 14 types
                        // pushed the fields off screen.
                        Picker("Service type", selection: $viewModel.kind) {
                            ForEach(ServiceCategory.allCases, id: \.self) { category in
                                Section(category.title) {
                                    ForEach(category.kinds, id: \.self) { kind in
                                        Text(kind.displayName).tag(kind)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section {
                    TextField("Name", text: $viewModel.name, prompt: Text(verbatim: viewModel.kind.displayName))
                    if let fixedURL = viewModel.kind.fixedURL {
                        LabeledContent("Server URL") {
                            Text(verbatim: fixedURL.absoluteString)
                        }
                    } else {
                        TextField("Server URL", text: $viewModel.urlText, prompt: Text(verbatim: ServiceHelp.urlPlaceholder(for: viewModel.kind)))
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    if let message = viewModel.urlValidationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    credentialFields
                    if let message = viewModel.credentialValidationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section("Help for this service type") {
                    Text(ServiceHelp.text(for: viewModel.kind))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // Commands (pveum…) can be copied.
                        .textSelection(.enabled)
                    NavigationLink {
                        GuideView(topic: .service(viewModel.kind))
                    } label: {
                        Label("See the full guide", systemImage: "book")
                    }
                }
                Section {
                    testResultView
                    Button("Test connection") {
                        viewModel.startTest()
                    }
                    .disabled(!viewModel.canTest)
                    if let saveError = viewModel.saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    if !viewModel.isEditing {
                        Text("The service can only be saved after a successful connection test.")
                    } else if viewModel.requiresNewCredential {
                        Text("New server: enter the credential again. The stored one is never sent to another address.")
                    } else if viewModel.requiresTest {
                        Text("The URL or the credential changed: test the connection before saving. Until then, the current settings stay in use.")
                    } else {
                        Text("Leave the credential empty to keep the current one. A new URL or credential must pass a connection test before it is saved.")
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? Text("Edit service") : Text("Add a service"))
            .onDisappear { viewModel.cancelTest() }
            .interactiveDismissDisabled(isSaving)
            .privacyCover()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            if await viewModel.save() { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(!viewModel.canSave || isSaving)
                }
            }
        }
    }

    /// One secure field, or separate user and password fields for Basic
    /// authentication (composed into user:password). Never pre-filled.
    @ViewBuilder
    private var credentialFields: some View {
        let kind = viewModel.kind
        let unchanged = Text("Unchanged")
        switch kind.credentialShape {
        case .single:
            if kind != .uptimeKuma {
                SecureField(
                    ServiceHelp.credentialLabel(for: kind),
                    text: $viewModel.token,
                    prompt: viewModel.isEditing ? unchanged : Text(verbatim: ServiceHelp.credentialPlaceholder(for: kind))
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        case .pair(let userIsEmail):
            let optional = !kind.requiresCredential
            TextField(
                userIsEmail ? String(localized: "E-mail") : String(localized: "User"),
                text: $viewModel.username,
                prompt: viewModel.isEditing ? unchanged : (optional ? Text("User (optional)") : nil)
            )
            // No .username/.password content type: no offer to save these
            // credentials outside the app's Keychain item.
            .keyboardType(userIsEmail ? .emailAddress : .default)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            SecureField(
                String(localized: "Password"),
                text: $viewModel.password,
                prompt: viewModel.isEditing ? unchanged : (optional ? Text("Password (optional)") : nil)
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        switch viewModel.testResult {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView("Testing connection…")
        case .success:
            Label("Connection successful", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
