import SwiftUI
import PatchNodeCore

/// Why a service failed, followed by when an automatic pause ends
/// ("Paused, resumes in 0:25", counting down on its own).
func serviceStateText(_ state: ServiceLoadState?, pause: ServicePauses.Pause?) -> Text {
    let message = state?.message ?? ""
    guard let pause, let resumeAt = pause.resumeAt else { return Text(message) }
    guard resumeAt > .now else {
        return Text("\(message) Retrying…")
    }
    let countdown = Text(timerInterval: Date.now...resumeAt, countsDown: true)
    return Text("\(message) Paused, resumes in \(countdown).")
}

extension ServiceStore {
    /// `serviceStateText` for one of this store's services.
    func stateText(for serviceID: UUID) -> Text {
        serviceStateText(states[serviceID], pause: pause(for: serviceID))
    }
}

/// Section listing the services of a screen that failed, with the reason.
struct ServiceErrorsSection: View {
    let services: [ServiceDescriptor]
    let states: [UUID: ServiceLoadState]
    var pauses: ServicePauses = ServicePauses()

    var body: some View {
        let failing = services.filter { states[$0.id]?.isFailure ?? false }
        if !failing.isEmpty {
            Section {
                ForEach(failing) { service in
                    Label {
                        VStack(alignment: .leading) {
                            Text(service.name).font(.headline)
                            serviceStateText(states[service.id], pause: pauses.pause(for: service.id))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            GuideHelpButton(kind: service.kind, state: states[service.id])
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

/// Frame shared by the dashboard cards of Phase 6 services: title, traffic
/// light (or a spinner until the first load), content, failures and age.
struct DashboardCardShell<Content: View>: View {
    let title: Text
    let systemImage: String
    let level: HealthLevel?
    let hasLoadedOnce: Bool
    let failures: [ServiceFailure]
    let lastUpdated: Date?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    title
                } icon: {
                    Image(systemName: systemImage)
                }
                .font(.headline)
                Spacer()
                if let level {
                    HealthIndicator(level: level)
                } else {
                    ProgressView()
                }
            }
            if hasLoadedOnce {
                content()
                ForEach(failures) { failure in
                    Label("\(failure.name): \(failure.message)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if let lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A failed service and why, for a dashboard card.
struct ServiceFailure: Identifiable {
    let id: UUID
    let name: String
    /// Reason, with the automatic-resume countdown when paused.
    let message: Text
}

extension ServiceStore {
    /// Failed services of the given kind (all when nil), for a dashboard card.
    func failures(kind: ServiceKind? = nil) -> [ServiceFailure] {
        services
            .filter { kind == nil || $0.kind == kind }
            .compactMap { service in
                states[service.id]?.message.map { _ in
                    ServiceFailure(id: service.id, name: service.name, message: stateText(for: service.id))
                }
            }
    }
}
