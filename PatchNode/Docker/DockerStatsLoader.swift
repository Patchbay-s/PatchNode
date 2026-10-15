import Foundation
import Observation
import PatchNodeCore
import DockerKit
import ProxmoxKit

/// CPU/RAM of running containers for the Docker tab. Docker's
/// `stats?stream=false` waits for a second sample (~1–2 s per container), so
/// requests are bounded in number and parallelism, skipped while the previous
/// sweep is recent, and only made while the tab is visible.
@Observable
@MainActor
final class DockerStatsLoader {
    /// Parallel stats requests across all hosts.
    nonisolated static let maxConcurrentRequests = 4
    /// Containers sampled per sweep; beyond that, sweeps rotate through the list.
    static let maxContainersPerSweep = 60
    /// No new request is started after this; requests in flight finish.
    static let sweepBudget: TimeInterval = 45

    /// Keyed by `DockerInventory.ContainerItem.id`.
    private(set) var stats: [String: DockerStats] = [:]
    private var lastSweep: Date?
    private var sweepTask: Task<Void, Never>?
    /// Where the next sweep starts when there are more running containers than
    /// `maxContainersPerSweep`.
    private var rotation = 0

    /// Starts a sweep in the background (pull to refresh doesn't wait for it).
    func start(for items: [DockerInventory.ContainerItem], store: DockerStore, maxAge: Int, force: Bool = false) {
        if force { cancel() }
        guard sweepTask == nil else { return }
        if !force, let lastSweep, Date.now.timeIntervalSince(lastSweep) < Double(maxAge) { return }
        sweepTask = Task {
            await sweep(items, store: store)
            // A cancelled sweep may end after its replacement started: leave the
            // replacement's reference alone so it can still be cancelled.
            guard !Task.isCancelled else { return }
            sweepTask = nil
        }
    }

    /// Called when the tab disappears; values already received are kept.
    func cancel() {
        sweepTask?.cancel()
        sweepTask = nil
    }

    private func sweep(_ items: [DockerInventory.ContainerItem], store: DockerStore) async {
        let running = items.filter(\.container.isRunning)
        // Forget containers that are gone or stopped.
        let runningIDs = Set(running.map(\.id))
        stats = stats.filter { runningIDs.contains($0.key) }
        guard !running.isEmpty else {
            lastSweep = .now
            return
        }

        let count = min(running.count, Self.maxContainersPerSweep)
        let start = rotation % running.count
        let selected = (0..<count).map { running[(start + $0) % running.count] }
        rotation = (start + count) % running.count

        var jobs: [(item: DockerInventory.ContainerItem, client: DockerClient)] = []
        var clients: [UUID: DockerClient?] = [:]
        for item in selected {
            guard !Task.isCancelled else { return }
            if clients[item.serviceID] == nil {
                clients[item.serviceID] = .some(await store.client(for: item.serviceID))
            }
            guard let client = clients[item.serviceID] ?? nil else { continue }
            jobs.append((item, client))
        }

        let deadline = Date.now.addingTimeInterval(Self.sweepBudget)
        await withTaskGroup(of: Result?.self) { group in
            var rejectedServices = Set<UUID>()
            var next = 0

            func addNext() {
                guard Date.now < deadline, !Task.isCancelled else { return }
                while next < jobs.count, rejectedServices.contains(jobs[next].item.serviceID) {
                    next += 1
                }
                guard next < jobs.count else { return }
                let (item, client) = jobs[next]
                next += 1
                group.addTask {
                    do {
                        let value = try await client.stats(on: item.host, containerID: item.container.id)
                        return Result(item: item, outcome: .success(value))
                    } catch is CancellationError {
                        return nil
                    } catch {
                        let state = ServiceLoadState(error: error)
                        // Only a refusal matters here (token, rights, proxy); other errors keep the old value.
                        guard state.pausesRequests else { return nil }
                        return Result(item: item, outcome: .failure(state))
                    }
                }
            }

            for _ in 0..<Self.maxConcurrentRequests { addNext() }
            // Results are published as they arrive (this loop runs on the main actor).
            for await result in group {
                if let result {
                    switch result.outcome {
                    case .success(let value):
                        stats[result.item.id] = value
                    case .failure(let state):
                        // A refused token stops the remaining requests to that service.
                        rejectedServices.insert(result.item.serviceID)
                        store.reportRejectedToken(for: result.item.serviceID, state: state)
                    }
                }
                addNext()
            }
        }
        if !Task.isCancelled { lastSweep = .now }
    }

    private nonisolated enum Outcome: Sendable {
        case success(DockerStats)
        case failure(ServiceLoadState)
    }

    private nonisolated struct Result: Sendable {
        let item: DockerInventory.ContainerItem
        let outcome: Outcome
    }
}
