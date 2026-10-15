import Foundation
import PatchNodeCore
import ProxmoxKit

/// A Proxmox terminal (node shell, CT, VM serial port) through termproxy and
/// its websocket. Every `open` asks a new one-time ticket.
public struct ProxmoxTerminalConnector: TerminalConnector {
    public let kind: TerminalKind = .proxmoxTerminal
    private let client: ProxmoxClient
    private let target: ProxmoxConsoleTarget
    private let serial: String?

    public init(client: ProxmoxClient, target: ProxmoxConsoleTarget, serial: String?) {
        self.client = client
        self.target = target
        self.serial = serial
    }

    public func open(size: TerminalSize) async throws -> any TerminalChannel {
        let ticket: ProxmoxConsoleTicket
        do {
            ticket = try await client.termProxy(target, serial: serial)
        } catch {
            throw ConsoleFailure(error)
        }
        let socket = try ConsoleWebSocket(
            url: try client.consoleWebSocketURL(target, ticket: ticket),
            headers: client.consoleAuthorizationHeaders
        )
        let first = try await socket.open(sending: TermProxyProtocol.handshake(user: ticket.user, ticket: ticket.ticket))
        guard TermProxyProtocol.isAccepted(first) else {
            socket.close()
            throw ConsoleFailure.handshakeFailed
        }
        let channel = ProxmoxTerminalChannel(socket: socket, initial: TermProxyProtocol.outputAfterAcceptance(first))
        await channel.resize(size)
        return channel
    }
}

final class ProxmoxTerminalChannel: TerminalChannel {
    let output: AsyncThrowingStream<[UInt8], any Error>
    private let socket: ConsoleWebSocket
    private let tasks = TaskBag()

    init(socket: ConsoleWebSocket, initial: Data) {
        self.socket = socket
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self)
        output = stream
        if !initial.isEmpty { continuation.yield(Array(initial)) }
        let reader = Task {
            do {
                while !Task.isCancelled {
                    let data = try await socket.receive()
                    if !data.isEmpty { continuation.yield(Array(data)) }
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
                try? await Task.sleep(for: TermProxyProtocol.keepAliveInterval)
                if Task.isCancelled { break }
                try? await socket.send(TermProxyProtocol.keepAlive)
            }
        }
        tasks.add(reader)
        tasks.add(keepAlive)
        continuation.onTermination = { [tasks] _ in tasks.cancelAll() }
    }

    func send(_ bytes: [UInt8]) async {
        try? await socket.send(TermProxyProtocol.input(bytes))
    }

    func resize(_ size: TerminalSize) async {
        try? await socket.send(TermProxyProtocol.resize(columns: size.columns, rows: size.rows))
    }

    func close() async {
        tasks.cancelAll()
        socket.close()
    }
}
