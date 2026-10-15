import AppIntents
import Foundation
import LocalAuthentication
import SwiftData
import PatchNodeCore
import ProxmoxKit
import DockerKit

// App Intents run in the app process, possibly without any UI. Entities and
// queries are `nonisolated`: the target defaults to MainActor isolation, but the
// system calls queries from its own executors. The restart intents stay on the
// main actor: their `@Parameter` stored properties cannot be `nonisolated`, and
// their network work runs in the clients' own isolation.

// MARK: - Service lookup

/// Finds a service's URL (SwiftData) and token (Keychain) from its ID, which is
/// all the shared snapshot carries.
@MainActor
enum IntentServices {
    static func descriptor(_ id: UUID) -> ServiceDescriptor? {
        guard let container = AppModelContainer.shared else { return nil }
        let context = ModelContext(container)
        var fetch = FetchDescriptor<ServiceConfig>(predicate: #Predicate { $0.id == id })
        fetch.fetchLimit = 1
        guard let config = try? context.fetch(fetch).first, let url = config.url else { return nil }
        return ServiceDescriptor(id: config.id, kind: config.kind, name: config.name, url: url)
    }
}

nonisolated enum IntentClients {
    /// Only the token saved for this service's server (`CredentialOrigin`).
    static func token(for service: ServiceDescriptor) async -> String? {
        guard let origin = CredentialOrigin.of(service.url),
              let token = try? await KeychainSecretStore().read(for: service.id, origin: origin), !token.isEmpty
        else { return nil }
        return token
    }

    static func proxmox(_ serviceID: UUID) async -> ProxmoxClient? {
        guard let service = await IntentServices.descriptor(serviceID), service.kind == .proxmoxVE,
              let token = await token(for: service)
        else { return nil }
        return ProxmoxClient(baseURL: service.url, apiTokenValue: token)
    }

    static func docker(_ serviceID: UUID) async -> DockerClient? {
        guard let service = await IntentServices.descriptor(serviceID), service.kind.isDocker else { return nil }
        let token = await token(for: service) ?? ""
        if service.kind.requiresCredential && token.isEmpty { return nil }
        return DockerClient(flavor: service.kind.dockerFlavor, baseURL: service.url, credential: token, engineName: service.name)
    }

    static func snapshot() -> SharedSnapshot? {
        SharedSnapshotStore.appGroup()?.read()
    }
}

// MARK: - HomeLab status

nonisolated struct HomeLabStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "HomeLab status" }
    static var description: IntentDescription {
        IntentDescription("Says the state saved by PatchNode at its last refresh, without contacting your services.")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = IntentClients.snapshot(), !snapshot.families.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "No data yet: open PatchNode once.")))
        }
        let age = RelativeDateTimeFormatter().localizedString(for: snapshot.generatedAt, relativeTo: .now)
        let text: String
        // Counts only: Siri may answer with the device locked.
        if snapshot.alertCount == 0 {
            text = String(localized: "All \(snapshot.okCount) services are OK. Last data \(age).")
        } else {
            text = String(localized: "\(snapshot.alertCount) in alert, \(snapshot.okCount) OK. Last data \(age).")
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - VM / container entities

nonisolated struct GuestEntity: AppEntity {
    let target: SharedSnapshot.GuestTarget
    var id: String { target.id }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "VM or container") }
    static var defaultQuery: GuestEntityQuery { GuestEntityQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(target.name)", subtitle: "\(Self.label(target)) · \(target.serviceName)")
    }

    /// "VM 100" / "CT 101".
    static func label(_ target: SharedSnapshot.GuestTarget) -> String {
        "\(target.type == "lxc" ? "CT" : "VM") \(target.vmid)"
    }
}

nonisolated struct GuestEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GuestEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [GuestEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        return all().filter { $0.target.name.localizedStandardContains(query) || String($0.target.vmid) == query }
    }

    func suggestedEntities() async throws -> [GuestEntity] {
        all()
    }

    private func all() -> [GuestEntity] {
        (IntentClients.snapshot()?.guests ?? []).map { GuestEntity(target: $0) }
    }
}

nonisolated struct ContainerEntity: AppEntity {
    let target: SharedSnapshot.ContainerTarget
    var id: String { target.id }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Container") }
    static var defaultQuery: ContainerEntityQuery { ContainerEntityQuery() }

    var displayRepresentation: DisplayRepresentation {
        // A socket-proxy engine is named after its service: don't say it twice.
        DisplayRepresentation(title: "\(target.name)", subtitle: target.endpointID == nil ? "\(target.serviceName)" : "\(target.host) · \(target.serviceName)")
    }
}

nonisolated struct ContainerEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ContainerEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ContainerEntity] {
        let query = string.trimmingCharacters(in: .whitespaces)
        return all().filter { $0.target.name.localizedStandardContains(query) }
    }

    func suggestedEntities() async throws -> [ContainerEntity] {
        all()
    }

    private func all() -> [ContainerEntity] {
        (IntentClients.snapshot()?.containers ?? []).map { ContainerEntity(target: $0) }
    }
}

// MARK: - Restart intents

/// Restarts a VM or LXC (clean reboot). The device must be unlocked (Face ID or
/// passcode), the user confirms with the target's name, and the POST is sent
/// once, never retried.
struct RestartGuestIntent: AppIntent {
    static var title: LocalizedStringResource { "Restart a VM" }
    static var description: IntentDescription {
        IntentDescription("Restarts a Proxmox VM or container after a confirmation naming it.")
    }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "VM or container")
    var guest: GuestEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Restart \(\.$guest)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let refusal = IntentDeviceSecurity.refusal { return .result(dialog: refusal) }
        let target = guest.target
        guard let actionTarget = ProxmoxActionTarget(shared: target),
              let service = await IntentServices.descriptor(target.serviceID),
              let client = await IntentClients.proxmox(target.serviceID)
        else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "The service is unavailable; nothing was sent.")))
        }
        // The shared snapshot may be old (VMID reused) or altered: the name shown in
        // the confirmation is read from the server and must match the one picked.
        let current: ProxmoxGuestStatus
        do {
            current = try await client.guestStatus(node: actionTarget.node, type: actionTarget.type, vmid: actionTarget.vmid)
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "The VM couldn't be read; nothing was sent. Check in PatchNode.")))
        }
        guard let currentName = current.name, currentName == target.name else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "This VM changed since PatchNode last refreshed; nothing was sent. Open PatchNode and try again.")))
        }
        let name = "\(GuestEntity.label(target)) “\(currentName)” (\(service.name) · \(actionTarget.node))"
        try await requestConfirmation(
            dialog: IntentDialog(stringLiteral: String(localized: "Restart \(name)?"))
        )
        do {
            let upid = try await client.perform(.reboot, node: actionTarget.node, type: actionTarget.type, vmid: actionTarget.vmid)
            let status = try await client.waitForTask(node: actionTarget.node, upid: upid, timeout: 20)
            let text = status.succeeded
                ? String(localized: "\(name) restarted.")
                : String(localized: "The restart of \(name) failed: \(status.exitStatus ?? "?").")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch ProxmoxActionError.taskTimedOut {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Restart of \(name) requested; still running. Check Recent tasks.")))
        } catch ServiceProviderError.forbidden {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Refused: the token needs the VM.PowerMgmt privilege for actions (e.g. a PatchNodePower role).")))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "The restart of \(name) couldn't be sent or confirmed. Check in PatchNode.")))
        }
    }
}

/// Restarts a Docker container, with the same rules as `RestartGuestIntent`.
struct RestartContainerIntent: AppIntent {
    static var title: LocalizedStringResource { "Restart a container" }
    static var description: IntentDescription {
        IntentDescription("Restarts a Docker container after a confirmation naming it.")
    }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Container")
    var container: ContainerEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Restart \(\.$container)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let refusal = IntentDeviceSecurity.refusal { return .result(dialog: refusal) }
        let target = container.target
        guard let service = await IntentServices.descriptor(target.serviceID),
              let client = await IntentClients.docker(target.serviceID)
        else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "The service is unavailable; nothing was sent.")))
        }
        let host = DockerHost(shared: target)
        // Same check as for VMs: the name comes from the server, not the snapshot.
        let currentName: String?
        do {
            currentName = try await client.details(on: host, containerID: target.containerID).name
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "The container couldn't be read; nothing was sent. Check in PatchNode.")))
        }
        guard let currentName, currentName == target.name else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "This container changed since PatchNode last refreshed; nothing was sent. Open PatchNode and try again.")))
        }
        let name = target.endpointID == nil
            ? "“\(currentName)” (\(service.name))"
            : "“\(currentName)” (\(target.host) · \(service.name))"
        try await requestConfirmation(
            dialog: IntentDialog(stringLiteral: String(localized: "Restart the container \(name)?"))
        )
        let sentAt = Date.now
        do {
            _ = try await client.perform(.restart, on: host, containerID: target.containerID)
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "\(name) restarted.")))
        } catch ServiceProviderError.unreachable {
            // A restart often outlasts the 10 s timeout: read the state, never resend.
            let confirmed = (try? await client.confirm(.restart, on: host, containerID: target.containerID, since: sentAt, timeout: 20)) ?? false
            let text = confirmed
                ? String(localized: "\(name) restarted (confirmed by reading its state).")
                : String(localized: "No answer in time for \(name); nothing was sent again. Check in PatchNode.")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch ServiceProviderError.forbidden {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Actions are disabled on this service.")))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "The restart of \(name) couldn't be sent. Check in PatchNode.")))
        }
    }
}

// MARK: - Shortcuts

nonisolated struct PatchNodeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HomeLabStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "HomeLab status with \(.applicationName)",
                "État du HomeLab avec \(.applicationName)",
            ],
            shortTitle: "HomeLab status",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: RestartGuestIntent(),
            phrases: [
                "Restart a VM with \(.applicationName)",
                "Redémarrer une VM avec \(.applicationName)",
            ],
            shortTitle: "Restart a VM",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: RestartContainerIntent(),
            phrases: [
                "Restart a container with \(.applicationName)",
                "Redémarrer un conteneur avec \(.applicationName)",
            ],
            shortTitle: "Restart a container",
            systemImageName: "shippingbox"
        )
    }
}

/// Actions from Shortcuts or Siri need a device passcode: without one,
/// `.requiresLocalDeviceAuthentication` lets anyone through, and the app itself
/// only opens its demo.
nonisolated enum IntentDeviceSecurity {
    static var refusal: IntentDialog? {
        // Siri and Shortcuts only need the iPhone unlocked, not PatchNode's own
        // Face ID: actions from them are off until the user turns them on.
        guard IntentActionSettings.isOn else {
            return IntentDialog(stringLiteral: String(localized: "Actions from Siri and Shortcuts are off. Turn them on in PatchNode › Settings, or act from the app; nothing was sent."))
        }
        var error: NSError?
        guard !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error),
              error?.code == LAError.Code.passcodeNotSet.rawValue
        else { return nil }
        return IntentDialog(stringLiteral: String(localized: "Set a passcode on this iPhone to run actions; nothing was sent."))
    }
}

/// Whether Siri and Shortcuts may run actions (restart a VM or a container).
/// Off by default: unlike the app, they don't ask for PatchNode's Face ID, so
/// anyone holding the unlocked iPhone could run them.
nonisolated enum IntentActionSettings {
    /// UserDefaults key (a Bool, no secret).
    static let key = "intentActionsEnabled"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
