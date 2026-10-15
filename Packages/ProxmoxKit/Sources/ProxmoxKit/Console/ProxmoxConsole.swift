import Foundation
import PatchNodeCore

/// What a console opens on: a node's shell, or a guest.
public enum ProxmoxConsoleTarget: Sendable, Hashable {
    case node(String)
    case guest(node: String, type: ProxmoxGuestType, vmid: Int)

    public var node: String {
        switch self {
        case .node(let node), .guest(let node, _, _): node
        }
    }

    /// The ACL path whose privilege the console needs.
    public var permissionPath: String {
        switch self {
        case .node(let node): "/nodes/\(node)"
        case .guest(_, _, let vmid): "/vms/\(vmid)"
        }
    }

    /// `Sys.Console` for a node's shell, `VM.Console` for a guest.
    public var requiredPrivilege: String {
        switch self {
        case .node: "Sys.Console"
        case .guest: "VM.Console"
        }
    }
}

/// `POST …/termproxy` or `…/vncproxy`: a one-time ticket for one websocket on
/// `port`, valid a few seconds. Never logged, never put in a loaded page.
public struct ProxmoxConsoleTicket: Sendable, Hashable, Decodable {
    public let port: Int
    public let ticket: String
    /// The authenticated identity, `user@realm!tokenid` for a token: sent back
    /// in the termproxy handshake.
    public let user: String

    public init(port: Int, ticket: String, user: String) {
        self.port = port; self.ticket = ticket; self.user = user
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let port = c.lenientInt(AnyCodingKey("port")), (1...65535).contains(port),
              let ticket = c.lenientString(AnyCodingKey("ticket")), !ticket.isEmpty,
              let user = c.lenientString(AnyCodingKey("user")), !user.isEmpty
        else { throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "incomplete console ticket")) }
        self.port = port; self.ticket = ticket; self.user = user
    }
}

public enum ProxmoxConsoleKind: Sendable, Hashable {
    /// xterm.js-style terminal through termproxy (node, CT, VM with `serialN`).
    case terminal(serial: String?)
    /// noVNC: a VM without a serial port.
    case graphical
}

/// Any JSON value, only to read keys and 0/1 flags of loosely typed objects.
struct ProxmoxJSONValue: Decodable, Sendable {
    let isTruthy: Bool

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let int = try? c.decode(Int.self) { isTruthy = int != 0 }
        else if let bool = try? c.decode(Bool.self) { isTruthy = bool }
        else if let string = try? c.decode(String.self) { isTruthy = !string.isEmpty && string != "0" }
        else { isTruthy = !c.decodeNil() }
    }
}

extension ProxmoxClient {
    /// Terminal for a CT and a node; for a VM, its first serial port if it has
    /// one (`GET …/qemu/{vmid}/config`, VM.Audit), else the graphical console.
    /// termproxy is never tried on a VM without a serial port (it fails with
    /// a 500).
    public func consoleKind(for target: ProxmoxConsoleTarget) async throws -> ProxmoxConsoleKind {
        guard case .guest(let node, .qemu, let vmid) = target else { return .terminal(serial: nil) }
        let config: [String: ProxmoxJSONValue] = try await objectValue(
            ["nodes", try Self.nodeSegment(node), "qemu", String(vmid), "config"]
        )
        return Self.serialPort(inConfigKeys: config.keys).map { .terminal(serial: $0) } ?? .graphical
    }

    /// `serial0`…`serial3`, the lowest present.
    static func serialPort(inConfigKeys keys: some Sequence<String>) -> String? {
        let present = Set(keys)
        return (0...3).map { "serial\($0)" }.first { present.contains($0) }
    }

    /// The token's own effective privileges on `path` (`GET /access/permissions`,
    /// needs no privilege). Privilege separation applies: what the token can do.
    public func privileges(on path: String) async throws -> Set<String> {
        let all: [String: [String: ProxmoxJSONValue]] = try await objectValue(
            ["access", "permissions"], query: [URLQueryItem(name: "path", value: path)]
        )
        return Set((all[path] ?? [:]).filter { $0.value.isTruthy }.keys)
    }

    /// POST: never retried. Starts the terminal proxy for one websocket.
    public func termProxy(_ target: ProxmoxConsoleTarget, serial: String? = nil) async throws -> ProxmoxConsoleTicket {
        var form: [URLQueryItem] = []
        if let serial {
            guard Self.serialPort(inConfigKeys: [serial]) != nil else { throw ServiceProviderError.invalidResponse }
            form.append(URLQueryItem(name: "serial", value: serial))
        }
        return try await postForm(try Self.consolePath(target) + ["termproxy"], form: form)
    }

    /// POST: never retried. VNC proxy for a VM, websocket mode; the ticket is
    /// also the VNC password.
    public func vncProxy(_ target: ProxmoxConsoleTarget) async throws -> ProxmoxConsoleTicket {
        guard case .guest(_, .qemu, _) = target else { throw ServiceProviderError.invalidResponse }
        return try await postForm(try Self.consolePath(target) + ["vncproxy"], form: [URLQueryItem(name: "websocket", value: "1")])
    }

    /// `wss://…/vncwebsocket?port=&vncticket=`: the ticket must be in the query
    /// (Proxmox's API); the app's request log never keeps query values.
    public func consoleWebSocketURL(_ target: ProxmoxConsoleTarget, ticket: ProxmoxConsoleTicket) throws -> URL {
        let http = url(try Self.consolePath(target) + ["vncwebsocket"])
        guard var components = URLComponents(url: http, resolvingAgainstBaseURL: false), components.scheme == "https" else {
            throw ServiceProviderError.invalidResponse
        }
        components.scheme = "wss"
        components.percentEncodedQuery = "port=\(ticket.port)&vncticket=\(Self.queryEncoded(ticket.ticket))"
        guard let url = components.url else { throw ServiceProviderError.invalidResponse }
        return url
    }

    /// Strict: only unreserved characters stay as is (`+`, `/`, `=`, `:` of a
    /// ticket are encoded).
    static func queryEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// The `pveum` lines granting this token the console of `target` (its
    /// identity only, never the secret).
    public func consoleAccessCommands(for target: ProxmoxConsoleTarget, keepingPower: Bool = false) -> [String] {
        ProxmoxConsoleAccess.commands(for: target, tokenValue: apiTokenValue, keepingPower: keepingPower)
    }

    /// The header the websocket upgrade must carry (PVE ≥ 9.1 accepts a token
    /// there).
    public var consoleAuthorizationHeaders: [String: String] {
        authorizationHeaders
    }

    static func consolePath(_ target: ProxmoxConsoleTarget) throws -> [String] {
        switch target {
        case .node(let node):
            return ["nodes", try nodeSegment(node)]
        case .guest(let node, let type, let vmid):
            guard vmid > 0 else { throw ServiceProviderError.invalidResponse }
            return ["nodes", try nodeSegment(node), type.rawValue, String(vmid)]
        }
    }
}

/// The `pveum` lines to grant a console, shown to copy when the token lacks the
/// privilege: `PatchNodeConsole` (VM.Console) on the guest only, or
/// `PatchNodeNodeConsole` (Sys.Console) on the node only, for the user and its
/// token, then the command that checks the result.
///
/// An ACL on a deeper path replaces, for the same user or token, the roles
/// inherited from above: alone on `/vms/101`, the console role would take away
/// PVEAuditor (VM.Audit) and the guest would vanish from the lists. So the
/// roles granted on the target always include PVEAuditor, and PatchNodePower
/// when the token can act on the guest today.
public enum ProxmoxConsoleAccess {
    public static let roleName = "PatchNodeConsole"
    public static let nodeRoleName = "PatchNodeNodeConsole"
    public static let auditorRole = "PVEAuditor"
    public static let powerRole = "PatchNodePower"

    /// The console role for `target` and its only privilege.
    public static func role(for target: ProxmoxConsoleTarget) -> (name: String, privilege: String) {
        switch target {
        case .node: (nodeRoleName, target.requiredPrivilege)
        case .guest: (roleName, target.requiredPrivilege)
        }
    }

    /// The roles to grant on `path` so that adding `role` keeps what was
    /// inherited: the role alone on `/`, PVEAuditor (and PatchNodePower when
    /// kept) with it anywhere deeper.
    public static func roles(adding role: String, on path: String, keepingPower: Bool = false) -> String {
        guard path != "/" else { return role }
        return ([auditorRole] + (keepingPower ? [powerRole] : []) + [role]).joined(separator: ",")
    }

    /// `user@realm` and `user@realm!tokenid` from the token value
    /// `user@realm!tokenid=secret` — the secret is never part of the result.
    public static func identities(fromTokenValue value: String) -> (user: String, token: String)? {
        guard let equal = value.firstIndex(of: "=") else { return nil }
        let token = String(value[..<equal])
        guard let bang = token.firstIndex(of: "!"), token[..<bang].contains("@") else { return nil }
        let user = String(token[..<bang])
        guard token.index(after: bang) < token.endIndex else { return nil }
        return (user, token)
    }

    /// `keepingPower`: the token holds VM.PowerMgmt on the guest today (from
    /// PatchNodePower on /vms, say), which an ACL on /vms/<id> would otherwise drop.
    public static func commands(for target: ProxmoxConsoleTarget, tokenValue: String, keepingPower: Bool = false) -> [String] {
        let role = role(for: target)
        let keepsPower = keepingPower && !isNode(target)
        let roles = roles(adding: role.name, on: target.permissionPath, keepingPower: keepsPower)
        guard let ids = identities(fromTokenValue: tokenValue),
              let path = try? ShellQuoting.quote(target.permissionPath),
              let user = try? ShellQuoting.quote(ids.user),
              let token = try? ShellQuoting.quote(ids.token),
              let tokenID = try? ShellQuoting.quote(String(ids.token.drop { $0 != "!" }.dropFirst())),
              let quotedRoles = try? ShellQuoting.quote(roles)
        else { return [] }
        // `role modify` without --append replaces the privileges: an older
        // PatchNodeConsole holding Sys.Console as well is narrowed.
        // VM.PowerMgmt may come from another role (PVEVMUser…): PatchNodePower
        // is created if missing, an existing one is left as is.
        let powerRole = keepsPower ? ["pveum role add \(powerRole) --privs VM.PowerMgmt || true"] : []
        return [
            "pveum role add \(role.name) --privs \(role.privilege) || pveum role modify \(role.name) --privs \(role.privilege)",
        ] + powerRole + [
            "pveum acl modify \(path) --roles \(quotedRoles) --users \(user)",
            "pveum acl modify \(path) --roles \(quotedRoles) --tokens \(token)",
            "pveum user token permissions \(user) \(tokenID) --path \(path)",
        ]
    }

    private static func isNode(_ target: ProxmoxConsoleTarget) -> Bool {
        if case .node = target { true } else { false }
    }
}
