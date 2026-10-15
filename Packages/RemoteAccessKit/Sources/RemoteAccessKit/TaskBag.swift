import Synchronization

/// Tasks owned by a connection, cancelled together when it closes.
final class TaskBag: Sendable {
    private let state = Mutex<(tasks: [Task<Void, Never>], cancelled: Bool)>(([], false))

    /// A task added after `cancelAll` is cancelled at once.
    func add(_ task: Task<Void, Never>) {
        let cancelled = state.withLock { state in
            if !state.cancelled { state.tasks.append(task) }
            return state.cancelled
        }
        if cancelled { task.cancel() }
    }

    func cancelAll() {
        let all = state.withLock { state in
            defer { state = ([], true) }
            return state.tasks
        }
        all.forEach { $0.cancel() }
    }
}
