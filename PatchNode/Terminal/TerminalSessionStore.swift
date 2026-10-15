import SwiftUI
import UIKit
import PatchNodeCore
import TerminalKit

enum SessionState: Equatable {
    case connecting
    case connected
    case ended(TerminalEndReason)
}

/// A tab of the workspace: a terminal (SSH, Proxmox) or a VM's graphical
/// console.
@MainActor
protocol WorkspaceSession: AnyObject {
    var id: UUID { get }
    var title: String { get }
    var subtitle: String { get }
    var state: SessionState { get }
    var failureMessage: String? { get }
    func connect()
    func close(reason: TerminalEndReason)
}

extension WorkspaceSession {
    var isLive: Bool {
        if case .ended = state { false } else { true }
    }
}

/// One terminal session: SSH or Proxmox console. Its screen (and scrollback)
/// lives as long as the session; its content is never stored or logged.
@Observable
@MainActor
final class TerminalSession: WorkspaceSession {
    let id = UUID()
    /// "web (CT 101)", "node-a", "storage-node".
    var title: String
    /// Where it runs: "SSH · storage-node", "Proxmox · node-a".
    let subtitle: String
    let connector: any TerminalConnector
    @ObservationIgnored let screen: TerminalScreen
    private(set) var state: SessionState = .connecting
    /// Shown under the terminal when the session ended with an error.
    private(set) var failureMessage: String?

    @ObservationIgnored private let logLabel: RequestLog.Label?
    @ObservationIgnored private var channel: (any TerminalChannel)?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var writer: Task<Void, Never>?
    @ObservationIgnored private var input: AsyncStream<[UInt8]>.Continuation?
    @ObservationIgnored private var openedAt: Date?

    init(title: String, subtitle: String, connector: any TerminalConnector, logLabel: RequestLog.Label?) {
        self.title = title
        self.subtitle = subtitle
        self.connector = connector
        self.logLabel = logLabel
        screen = TerminalScreen()
        // Keystrokes in order, through one writer task.
        screen.onInput = { [weak self] bytes in self?.input?.yield(bytes) }
        screen.onResize = { [weak self] size in
            guard let channel = self?.channel else { return }
            Task { await channel.resize(size) }
        }
    }

    func connect() {
        guard channel == nil, pump == nil else { return }
        state = .connecting
        failureMessage = nil
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        input = continuation
        pump = Task { [weak self, connector, screen] in
            let channel: any TerminalChannel
            do {
                channel = try await connector.open(size: screen.size)
            } catch {
                // Closed (or reconnected) meanwhile: this attempt ends nothing.
                guard !Task.isCancelled else { return }
                self?.end(.failed(code: Self.code(error)), message: Self.message(error))
                return
            }
            guard let self, !Task.isCancelled else {
                await channel.close()
                return
            }
            self.channel = channel
            self.state = .connected
            self.openedAt = .now
            RequestLog.shared.append(.event(.terminalOpened(connector.kind)), label: logLabel)
            self.writer = Task {
                for await bytes in stream { await channel.send(bytes) }
            }
            do {
                for try await chunk in channel.output {
                    screen.feed(chunk)
                }
                self.end(.closed, message: nil)
            } catch is CancellationError {
                // close() ended it.
            } catch {
                self.end(.failed(code: Self.code(error)), message: Self.message(error))
            }
        }
    }

    func close(reason: TerminalEndReason = .closed) {
        end(reason, message: nil)
    }

    private func end(_ reason: TerminalEndReason, message: String?) {
        guard isLive else { return }
        state = .ended(reason)
        failureMessage = message
        input?.finish()
        input = nil
        writer?.cancel()
        writer = nil
        pump?.cancel()
        pump = nil
        if let channel {
            Task { await channel.close() }
        }
        channel = nil
        let duration = openedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        openedAt = nil
        RequestLog.shared.append(.event(.terminalEnded(connector.kind, duration: duration, reason: reason)), label: logLabel)
        switch reason {
        case .closed: screen.showNotice(String(localized: "Session ended."))
        case .backgroundTimeout: screen.showNotice(String(localized: "Session closed while PatchNode was in the background."))
        case .failed: screen.showNotice(message ?? String(localized: "Connection lost."))
        }
    }

    private static func code(_ error: any Error) -> String {
        (error as? any TerminalFailure)?.code ?? "error"
    }

    private static func message(_ error: any Error) -> String {
        TerminalFailureText.message(for: error)
    }
}

/// The open terminal sessions of the app, shown in one workspace (tabs on
/// iPad and Mac). Closed in the background after a grace period; reopened
/// only by the user, with Face ID.
@Observable
@MainActor
final class TerminalSessionStore {
    static let maxSessions = 8
    /// Long enough to switch to another app and back (copy a command), short
    /// enough not to leave shells open on a pocketed iPhone.
    static let backgroundGrace: Duration = .seconds(30)

    private(set) var sessions: [any WorkspaceSession] = []
    var selectedID: UUID?
    var isPresented = false

    @ObservationIgnored private let authorize: (String) async -> Bool
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?

    init(authorize: @escaping (String) async -> Bool) {
        self.authorize = authorize
    }

    var selected: (any WorkspaceSession)? {
        sessions.first { $0.id == selectedID } ?? sessions.last
    }

    var liveCount: Int { sessions.filter(\.isLive).count }

    var canOpenMore: Bool { sessions.count < Self.maxSessions }

    /// Adds a session (the caller already asked for Face ID), selects it and
    /// shows the workspace.
    @discardableResult
    func open(title: String, subtitle: String, connector: any TerminalConnector, logLabel: RequestLog.Label?) -> TerminalSession? {
        guard canOpenMore else { return nil }
        let session = TerminalSession(title: title, subtitle: subtitle, connector: connector, logLabel: logLabel)
        add(session)
        return session
    }

    /// A VM's graphical console (the caller already asked for Face ID).
    @discardableResult
    func openGraphical(title: String, subtitle: String, link: GraphicalConsoleSession.Link, logLabel: RequestLog.Label?) -> GraphicalConsoleSession? {
        guard canOpenMore else { return nil }
        let session = GraphicalConsoleSession(title: title, subtitle: subtitle, link: link, logLabel: logLabel)
        add(session)
        return session
    }

    private func add(_ session: any WorkspaceSession) {
        sessions.append(session)
        selectedID = session.id
        isPresented = true
        session.connect()
    }

    /// A new connection for an ended session, after Face ID.
    func reconnect(_ session: any WorkspaceSession) async {
        guard !session.isLive else { return }
        guard await authorize(String(localized: "Reconnect \(session.title)")) else { return }
        (session as? TerminalSession)?.screen.showNotice(String(localized: "Reconnecting…"))
        session.connect()
    }

    func close(_ session: any WorkspaceSession) {
        session.close(reason: .closed)
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id { selectedID = sessions.last?.id }
        if sessions.isEmpty { isPresented = false }
    }

    func closeAll(reason: TerminalEndReason = .closed) {
        sessions.forEach { $0.close(reason: reason) }
    }

    func select(offset: Int) {
        guard let current = sessions.firstIndex(where: { $0.id == selected?.id }), !sessions.isEmpty else { return }
        selectedID = sessions[(current + offset + sessions.count) % sessions.count].id
    }

    // MARK: - Background

    func enterBackground() {
        guard liveCount > 0, backgroundTask == nil else { return }
        let application = UIApplication.shared
        let assertion = BackgroundAssertion()
        assertion.id = application.beginBackgroundTask(withName: "terminal-grace") { [weak self] in
            // Out of time: close now rather than be suspended with open sockets.
            self?.closeAll(reason: .backgroundTimeout)
            assertion.end()
        }
        backgroundTask = Task { [weak self] in
            try? await Task.sleep(for: Self.backgroundGrace)
            if !Task.isCancelled {
                self?.closeAll(reason: .backgroundTimeout)
                self?.backgroundTask = nil
            }
            assertion.end()
        }
    }

    func enterForeground() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }
}

/// A background task identifier, ended once.
@MainActor
private final class BackgroundAssertion {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
