import Foundation
import PatchNodeCore
import Synchronization

/// A simulated shell for the demo: a prompt, line editing (backspace) and a
/// few canned commands. Contacts nothing.
public struct DemoTerminalConnector: TerminalConnector {
    public let kind: TerminalKind = .demo
    public let hostname: String
    public let user: String
    /// Shown once connected ("Connected to the CT 101 console…").
    public let banner: String

    public init(hostname: String, user: String = "root", banner: String) {
        self.hostname = hostname
        self.user = user
        self.banner = banner
    }

    public func open(size: TerminalSize) async throws -> any TerminalChannel {
        DemoTerminalChannel(hostname: hostname, user: user, banner: banner)
    }
}

public final class DemoTerminalChannel: TerminalChannel {
    public let output: AsyncThrowingStream<[UInt8], any Error>
    private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let state: Mutex<State>
    private let prompt: String
    private let hostname: String

    private struct State {
        var line: [UInt8] = []
        var closed = false
    }

    public init(hostname: String, user: String, banner: String) {
        (output, continuation) = AsyncThrowingStream.makeStream()
        state = Mutex(State())
        self.hostname = hostname
        prompt = "\(user)@\(hostname):~# "
        continuation.yield(Array("\(banner)\r\n\r\n\(prompt)".utf8))
    }

    public func send(_ bytes: [UInt8]) async {
        var echo: [UInt8] = []
        var commands: [String] = []
        state.withLock { state in
            guard !state.closed else { return }
            for byte in bytes {
                switch byte {
                case 13, 10:
                    echo += Array("\r\n".utf8)
                    commands.append(String(decoding: state.line, as: UTF8.self))
                    state.line = []
                case 127, 8:
                    if !state.line.isEmpty {
                        state.line.removeLast()
                        echo += [8, 32, 8]
                    }
                case 3:
                    echo += Array("^C\r\n".utf8)
                    state.line = []
                    commands.append("")
                case 0x20...0x7E, 0x80...:
                    state.line.append(byte)
                    echo.append(byte)
                default:
                    break
                }
            }
        }
        if !echo.isEmpty { continuation.yield(echo) }
        for command in commands {
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            if trimmed == "exit" || trimmed == "logout" {
                continuation.yield(Array("logout\r\n".utf8))
                await close()
                return
            }
            let reply = Self.reply(to: trimmed, hostname: hostname)
            continuation.yield(Array((reply.isEmpty ? "" : reply + "\r\n").utf8) + Array(prompt.utf8))
        }
    }

    public func resize(_ size: TerminalSize) async {}

    public func close() async {
        let wasOpen = state.withLock { state in
            defer { state.closed = true }
            return !state.closed
        }
        if wasOpen { continuation.finish() }
    }

    /// Canned answers, in technical English like a real shell.
    static func reply(to command: String, hostname: String) -> String {
        let name = command.split(separator: " ").first.map(String.init) ?? ""
        switch name {
        case "": return ""
        case "help":
            return "Demo shell: try uptime, df -h, free -h, ls, docker ps, hostname, whoami, exit."
        case "hostname": return hostname
        case "whoami": return "root"
        case "uptime": return " 14:32:07 up 41 days,  3:12,  1 user,  load average: 0.42, 0.37, 0.31"
        case "ls": return "backups  docker-compose.yml  notes.txt"
        case "pwd": return "/root"
        case "df":
            return """
            Filesystem      Size  Used Avail Use% Mounted on\r
            /dev/sda1        32G  9.1G   21G  31% /\r
            tmpfs           1.0G     0  1.0G   0% /dev/shm
            """
        case "free":
            return """
                           total        used        free      shared  buff/cache   available\r
            Mem:           7.8Gi       2.1Gi       3.9Gi        12Mi       1.8Gi       5.4Gi\r
            Swap:          1.0Gi          0B       1.0Gi
            """
        case "docker":
            return """
            CONTAINER ID   IMAGE                 STATUS          NAMES\r
            3f2a1c9d8e7b   nginx:1.27            Up 3 days       proxy\r
            9b8c7d6e5f4a   postgres:17           Up 3 days       db
            """
        default:
            return "\(name): command simulated in the demo (try help)"
        }
    }
}
