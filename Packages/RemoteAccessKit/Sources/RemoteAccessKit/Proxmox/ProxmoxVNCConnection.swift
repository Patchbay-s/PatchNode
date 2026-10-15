import Foundation
import PatchNodeCore
import ProxmoxKit

/// The graphical console of a VM: a vncproxy ticket and its websocket, whose
/// raw RFB bytes the app relays to noVNC (embedded, offline). The token stays
/// in the upgrade header; noVNC only gets the one-time VNC password.
public final class ProxmoxVNCConnection: Sendable {
    /// What noVNC needs: the VNC password (the ticket), never the token.
    public let password: String
    public let output: AsyncThrowingStream<Data, any Error>
    private let socket: ConsoleWebSocket
    private let tasks = TaskBag()

    public static func open(client: ProxmoxClient, target: ProxmoxConsoleTarget) async throws -> ProxmoxVNCConnection {
        let ticket: ProxmoxConsoleTicket
        do {
            ticket = try await client.vncProxy(target)
        } catch {
            throw ConsoleFailure(error)
        }
        let socket = try ConsoleWebSocket(
            url: try client.consoleWebSocketURL(target, ticket: ticket),
            headers: client.consoleAuthorizationHeaders
        )
        // The RFB server speaks first ("RFB 003.008\n").
        let first = try await socket.open(sending: nil)
        return ProxmoxVNCConnection(socket: socket, password: ticket.ticket, first: first)
    }

    private init(socket: ConsoleWebSocket, password: String, first: Data) {
        self.socket = socket
        self.password = password
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        output = stream
        continuation.yield(first)
        let reader = Task {
            do {
                while !Task.isCancelled {
                    let data = try await socket.receive()
                    if !data.isEmpty { continuation.yield(data) }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let keepAlive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await socket.sendPing()
            }
        }
        tasks.add(reader)
        tasks.add(keepAlive)
        continuation.onTermination = { [tasks] _ in tasks.cancelAll() }
    }

    public func send(_ data: Data) async {
        try? await socket.send(data)
    }

    public func close() {
        tasks.cancelAll()
        socket.close()
    }
}
