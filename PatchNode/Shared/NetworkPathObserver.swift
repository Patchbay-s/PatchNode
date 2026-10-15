import Foundation
import Network

/// Calls `onChange` when the network path really changes (VPN such as Tailscale
/// toggled, Wi-Fi ↔ cellular), debounced: iOS reports several updates for one
/// change. The first update (the current path) is not a change.
@MainActor
final class NetworkPathObserver {
    private let monitor = NWPathMonitor()
    private var lastSignature: String?
    private var debounce: Task<Void, Never>?
    private var onChange: (() -> Void)?

    func start(onChange: @escaping () -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        // Main queue: updates are handled in order, on the main actor.
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.signature(of: path)
            MainActor.assumeIsolated { self?.received(signature) }
        }
        monitor.start(queue: .main)
    }

    private func received(_ signature: String) {
        guard let last = lastSignature else {
            lastSignature = signature
            return
        }
        guard signature != last else { return }
        lastSignature = signature
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    /// Status, interfaces (a VPN adds a utun interface) and gateways. Kept in
    /// memory only, never logged.
    private nonisolated static func signature(of path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map { "\($0.type)-\($0.name)" }.sorted()
        let gateways = path.gateways.map { "\($0)" }.sorted()
        return "\(path.status)|\(interfaces.joined(separator: ","))|\(gateways.joined(separator: ","))"
    }
}
