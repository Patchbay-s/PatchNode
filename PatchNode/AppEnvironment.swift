import SwiftUI
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

/// Every object the views read with `@Environment(Type.self)`, in one place.
/// Applied at the root of each scene, and again at the root of the
/// presentations that open sessions (workspace, console and SSH sheets): a
/// missing object is a crash, never a fallback. `scripts/check-environment.sh`
/// fails when a view reads a type that isn't listed here (keep the `as Type`).
struct AppEnvironment: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .environment(model as AppModel)
            .environment(model.lockController as AppLockController)
            .environment(model.actionLog as ActionLog)
            .environment(model.proxmoxStore as ProxmoxStore)
            .environment(model.dockerStore as DockerStore)
            .environment(model.observabilityStore as ObservabilityStore)
            .environment(model.backupStore as BackupStore)
            .environment(model.tailscaleStore as TailscaleStore)
            .environment(model.securityStore as SecurityStore)
            .environment(model.homeStore as HomeStore)
            .environment(model.terminals as TerminalSessionStore)
            .environment(model.consoles as ConsoleLauncher)
            .environment(model.ssh as SSHLauncher)
    }
}

extension View {
    func appEnvironment(_ model: AppModel) -> some View {
        modifier(AppEnvironment(model: model))
    }
}
