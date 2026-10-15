import SwiftUI

/// One action offered on a target (VM, container…).
struct ActionOption: Identifiable, Hashable {
    let id: String
    /// Button title, e.g. "Shut down".
    let title: String
    let systemImage: String
    /// Forced stop: shown in red, with a data-loss warning in the confirmation.
    let isForced: Bool
}

enum ActionOutcome {
    case succeeded(String)
    case failed(String)
}

/// Action buttons with the rules every state-changing action follows:
/// - a confirmation naming the target and the action,
/// - Face ID / passcode again if the last authentication is older than 5 minutes,
/// - buttons disabled while an action runs (no double tap), no automatic retry,
/// - the action and its result go to the session's action log.
struct ActionsSection: View {
    let options: [ActionOption]
    /// Stable identity of the target (service + node/host + id), for in-flight tracking.
    let targetKey: String
    /// e.g. "VM 100 “web” on pve".
    let targetDescription: String
    let serviceName: String
    /// Section header; "Actions" by default.
    var header: Text = Text("Actions")
    let perform: (ActionOption) async -> ActionOutcome

    @Environment(AppLockController.self) private var lockController
    @Environment(ActionLog.self) private var actionLog
    @State private var pending: ActionOption?
    @State private var running: ActionOption?
    @State private var lastOutcome: (option: ActionOption, outcome: ActionOutcome)?

    var body: some View {
        Section {
            ForEach(options) { option in
                Button {
                    pending = option
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .foregroundStyle(option.isForced ? Color.red : Color.accentColor)
                }
                .disabled(running != nil || actionLog.inFlightTargets.contains(targetKey))
            }
            if let running {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("\(running.title) in progress…")
                }
            } else if actionLog.inFlightTargets.contains(targetKey) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("An action is already running on this target.")
                }
            } else if let lastOutcome {
                switch lastOutcome.outcome {
                case .succeeded(let message):
                    Label("\(lastOutcome.option.title): \(message)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label("\(lastOutcome.option.title): \(message)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            header
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { option in
            Button(option.title, role: option.isForced ? .destructive : nil) {
                pending = nil
                // Claimed synchronously: a second confirmation can't slip in before the task starts.
                guard running == nil, actionLog.claim(targetKey) else { return }
                running = option
                Task { await run(option) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { option in
            if option.isForced {
                Text("Forced stop, like pulling the power plug: unsaved data in the guest may be lost. Prefer Shut down when possible. Target: \(targetDescription) (\(serviceName)).")
            } else {
                Text("Target: \(targetDescription) (\(serviceName)).")
            }
        }
    }

    private var dialogTitle: String {
        guard let pending else { return "" }
        return String(localized: "\(pending.title) \(targetDescription)?")
    }

    private func run(_ option: ActionOption) async {
        // `running` and the target claim were set by the confirmation button.
        defer {
            running = nil
            actionLog.release(targetKey)
        }
        let reason = String(localized: "Confirm “\(option.title)” on \(targetDescription)")
        guard await lockController.authenticateForAction(reason: reason) else {
            lastOutcome = (option, .failed(String(localized: "Authentication failed or cancelled; nothing was done.")))
            return
        }
        let entry = actionLog.begin(service: serviceName, target: targetDescription, action: option.title)
        let outcome = await perform(option)
        lastOutcome = (option, outcome)
        switch outcome {
        case .succeeded(let message): actionLog.finish(entry, .succeeded(message))
        case .failed(let message): actionLog.finish(entry, .failed(message))
        }
    }
}

struct ActionLogView: View {
    @Environment(ActionLog.self) private var actionLog

    var body: some View {
        List {
            if actionLog.entries.isEmpty {
                Text("No action in this session.")
                    .foregroundStyle(.secondary)
            }
            ForEach(actionLog.entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: entry.action).font(.headline)
                        Spacer()
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: "\(entry.target) · \(entry.service)")
                        .font(.subheadline)
                    switch entry.outcome {
                    case .inProgress:
                        Text("In progress…").font(.caption).foregroundStyle(.secondary)
                    case .succeeded(let message):
                        Text(verbatim: message).font(.caption).foregroundStyle(.green)
                    case .failed(let message):
                        Text(verbatim: message).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle("Actions this session")
    }
}
