import Foundation
import Observation

/// Actions performed during this app session (target, action, time, result).
/// In memory only, never persisted, and never contains a secret.
@Observable
@MainActor
final class ActionLog {
    struct Entry: Identifiable {
        enum Outcome {
            case inProgress
            case succeeded(String)
            case failed(String)
        }

        let id = UUID()
        let date: Date
        let service: String
        let target: String
        let action: String
        var outcome: Outcome
    }

    /// Oldest entries are dropped beyond this.
    static let capacity = 200

    private(set) var entries: [Entry] = []
    /// Targets with an action in flight, app-wide: leaving and reopening a screen
    /// must not allow a second POST on the same target.
    private(set) var inFlightTargets: Set<String> = []

    /// False if an action is already running on `target`.
    func claim(_ target: String) -> Bool {
        inFlightTargets.insert(target).inserted
    }

    func release(_ target: String) {
        inFlightTargets.remove(target)
    }

    @discardableResult
    func begin(service: String, target: String, action: String) -> UUID {
        let entry = Entry(date: .now, service: service, target: target, action: action, outcome: .inProgress)
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        return entry.id
    }

    func finish(_ id: UUID, _ outcome: Entry.Outcome) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].outcome = outcome
    }
}
