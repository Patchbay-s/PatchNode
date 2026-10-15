import Foundation
import Testing
import PatchNodeCore
@testable import ProxmoxKit

@Suite("Proxmox consoles")
struct ProxmoxConsoleTests {
    static let token = "test-user@pam!test-token=00000000-fake-0000-secret"
    static let baseURL = URL(string: "https://proxmox.example.invalid:8006")!

    private func client(_ fake: FakeHTTPClient) -> ProxmoxClient {
        ProxmoxClient(baseURL: Self.baseURL, apiTokenValue: Self.token, httpClient: fake)
    }

    @Test func termProxyPostsToTheGuestAndDecodesTheTicket() async throws {
        let fake = FakeHTTPClient.json(#"{"data":{"port":"5900","ticket":"PVEVNC:ABC+/=","user":"test-user@pam!test-token","upid":"UPID:x"}}"#)
        let ticket = try await client(fake).termProxy(.guest(node: "node-1", type: .lxc, vmid: 101))
        #expect(ticket == ProxmoxConsoleTicket(port: 5900, ticket: "PVEVNC:ABC+/=", user: "test-user@pam!test-token"))
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.method == .post)
        #expect(spec.url.path() == "/api2/json/nodes/node-1/lxc/101/termproxy")
        #expect(spec.body == nil)
    }

    @Test func vmSerialTerminalSendsItsSerialPort() async throws {
        let fake = FakeHTTPClient.json(#"{"data":{"port":5901,"ticket":"T","user":"test-user@pam!test-token"}}"#)
        _ = try await client(fake).termProxy(.guest(node: "node-1", type: .qemu, vmid: 100), serial: "serial0")
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(String(decoding: spec.body ?? Data(), as: UTF8.self) == "serial=serial0")
        #expect(spec.headers["Content-Type"] == "application/x-www-form-urlencoded")
    }

    @Test func anInvalidSerialPortIsNeverSent() async {
        let fake = FakeHTTPClient.json(#"{"data":{}}"#)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client(fake).termProxy(.guest(node: "node-1", type: .qemu, vmid: 100), serial: "serial0&cmd=x")
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func vncProxyAsksForWebsocketModeOnlyForVMs() async throws {
        let fake = FakeHTTPClient.json(#"{"data":{"port":5902,"ticket":"T","user":"test-user@pam!test-token","cert":"x"}}"#)
        _ = try await client(fake).vncProxy(.guest(node: "node-1", type: .qemu, vmid: 100))
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.path() == "/api2/json/nodes/node-1/qemu/100/vncproxy")
        #expect(String(decoding: spec.body ?? Data(), as: UTF8.self) == "websocket=1")
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await client(fake).vncProxy(.node("node-1"))
        }
    }

    @Test func incompleteTicketIsRefused() async {
        let fake = FakeHTTPClient.json(#"{"data":{"port":0,"ticket":"","user":"u"}}"#)
        await #expect(throws: (any Error).self) {
            _ = try await client(fake).termProxy(.node("node-1"))
        }
    }

    @Test func consoleKindFollowsTheSerialPort() async throws {
        let withSerial = FakeHTTPClient.json(#"{"data":{"name":"web","serial1":"socket","memory":"2048"}}"#)
        #expect(try await client(withSerial).consoleKind(for: .guest(node: "node-1", type: .qemu, vmid: 100)) == .terminal(serial: "serial1"))
        let without = FakeHTTPClient.json(#"{"data":{"name":"win","vga":"std"}}"#)
        #expect(try await client(without).consoleKind(for: .guest(node: "node-1", type: .qemu, vmid: 100)) == .graphical)
        // CTs and nodes: always a terminal, no request.
        let none = FakeHTTPClient.json("{}")
        #expect(try await client(none).consoleKind(for: .guest(node: "node-1", type: .lxc, vmid: 101)) == .terminal(serial: nil))
        #expect(try await client(none).consoleKind(for: .node("node-1")) == .terminal(serial: nil))
        #expect(await none.receivedSpecs.isEmpty)
    }

    @Test func privilegesOfTheTokenOnAPath() async throws {
        let fake = FakeHTTPClient.json(#"{"data":{"/vms/101":{"VM.Console":1,"VM.Audit":1,"VM.PowerMgmt":0}}}"#)
        let privileges = try await client(fake).privileges(on: "/vms/101")
        #expect(privileges == ["VM.Console", "VM.Audit"])
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.query() == "path=/vms/101")
    }

    @Test func websocketURLIsWssWithAnEncodedTicket() throws {
        let client = ProxmoxClient(baseURL: Self.baseURL, apiTokenValue: Self.token)
        let url = try client.consoleWebSocketURL(
            .guest(node: "node-1", type: .qemu, vmid: 100),
            ticket: ProxmoxConsoleTicket(port: 5900, ticket: "PVEVNC:A+b/c=::d", user: "u")
        )
        #expect(url.scheme == "wss")
        #expect(url.host() == "proxmox.example.invalid")
        #expect(url.port == 8006)
        #expect(url.path() == "/api2/json/nodes/node-1/qemu/100/vncwebsocket")
        #expect(url.query(percentEncoded: true) == "port=5900&vncticket=PVEVNC%3AA%2Bb%2Fc%3D%3A%3Ad")
        // The token is never part of the URL.
        #expect(!url.absoluteString.contains("secret"))
        #expect(client.consoleAuthorizationHeaders["Authorization"] == "PVEAPIToken=\(Self.token)")
    }

    @Test func nodeNamesThatCouldAlterThePathAreRefused() {
        let client = ProxmoxClient(baseURL: Self.baseURL, apiTokenValue: Self.token)
        let ticket = ProxmoxConsoleTicket(port: 1, ticket: "t", user: "u")
        #expect(throws: (any Error).self) { try client.consoleWebSocketURL(.node("../access"), ticket: ticket) }
        #expect(throws: (any Error).self) { try client.consoleWebSocketURL(.guest(node: "node-1", type: .lxc, vmid: 0), ticket: ticket) }
    }

    @Test func targetsNeedTheRightPrivilegeOnTheRightPath() {
        #expect(ProxmoxConsoleTarget.node("node-1").permissionPath == "/nodes/node-1")
        #expect(ProxmoxConsoleTarget.node("node-1").requiredPrivilege == "Sys.Console")
        #expect(ProxmoxConsoleTarget.guest(node: "node-1", type: .qemu, vmid: 7).permissionPath == "/vms/7")
        #expect(ProxmoxConsoleTarget.guest(node: "node-1", type: .qemu, vmid: 7).requiredPrivilege == "VM.Console")
    }

    @Test func accessCommandsNameTheTokenButNeverItsSecret() {
        let commands = ProxmoxConsoleAccess.commands(for: .guest(node: "node-1", type: .lxc, vmid: 101), tokenValue: Self.token)
        #expect(commands == [
            "pveum role add PatchNodeConsole --privs VM.Console || pveum role modify PatchNodeConsole --privs VM.Console",
            "pveum acl modify '/vms/101' --roles 'PVEAuditor,PatchNodeConsole' --users 'test-user@pam'",
            "pveum acl modify '/vms/101' --roles 'PVEAuditor,PatchNodeConsole' --tokens 'test-user@pam!test-token'",
            "pveum user token permissions 'test-user@pam' 'test-token' --path '/vms/101'",
        ])
        #expect(!commands.joined().contains("secret"))
    }

    /// An ACL on /vms/<id> replaces what the token inherits from / and /vms:
    /// PVEAuditor always comes along, PatchNodePower when the token has it now.
    @Test func guestCommandsKeepTheInheritedRoles() {
        let guest = ProxmoxConsoleTarget.guest(node: "node-1", type: .qemu, vmid: 7)
        let withPower = ProxmoxConsoleAccess.commands(for: guest, tokenValue: Self.token, keepingPower: true)
        #expect(withPower[1] == "pveum role add PatchNodePower --privs VM.PowerMgmt || true")
        #expect(withPower[2] == "pveum acl modify '/vms/7' --roles 'PVEAuditor,PatchNodePower,PatchNodeConsole' --users 'test-user@pam'")
        #expect(withPower[3] == "pveum acl modify '/vms/7' --roles 'PVEAuditor,PatchNodePower,PatchNodeConsole' --tokens 'test-user@pam!test-token'")
        for line in withPower + ProxmoxConsoleAccess.commands(for: guest, tokenValue: Self.token) {
            #expect(!line.contains("Sys.Console"))
            if line.contains("acl modify") { #expect(line.contains("PVEAuditor")) }
        }
    }

    /// Sys.Console only on the node, in its own role; never VM.Console there.
    @Test func nodeCommandsGrantSysConsoleOnTheNodeOnly() {
        let commands = ProxmoxConsoleAccess.commands(for: .node("node-1"), tokenValue: Self.token, keepingPower: true)
        #expect(commands == [
            "pveum role add PatchNodeNodeConsole --privs Sys.Console || pveum role modify PatchNodeNodeConsole --privs Sys.Console",
            "pveum acl modify '/nodes/node-1' --roles 'PVEAuditor,PatchNodeNodeConsole' --users 'test-user@pam'",
            "pveum acl modify '/nodes/node-1' --roles 'PVEAuditor,PatchNodeNodeConsole' --tokens 'test-user@pam!test-token'",
            "pveum user token permissions 'test-user@pam' 'test-token' --path '/nodes/node-1'",
        ])
        #expect(!commands.joined().contains("VM.Console"))
        #expect(!commands.joined().contains("/vms"))
    }

    @Test func onTheRootTheRoleAloneIsEnough() {
        #expect(ProxmoxConsoleAccess.roles(adding: "PatchNodeConsole", on: "/") == "PatchNodeConsole")
        #expect(ProxmoxConsoleAccess.roles(adding: "PatchNodeConsole", on: "/vms") == "PVEAuditor,PatchNodeConsole")
        #expect(ProxmoxConsoleAccess.roles(adding: "PatchNodePower", on: "/vms/3") == "PVEAuditor,PatchNodePower")
    }

    @Test func aTokenIDThatCouldAlterTheCommandYieldsNoCommand() {
        #expect(ProxmoxConsoleAccess.commands(for: .node("node-1"), tokenValue: "test-user@pam!t\u{1B}x=s").isEmpty)
        let quoted = ProxmoxConsoleAccess.commands(for: .node("node-1"), tokenValue: "test-user@pam!t'x=s")
        #expect(quoted.last == "pveum user token permissions 'test-user@pam' 't'\\''x' --path '/nodes/node-1'")
    }

    @Test func identitiesNeedAUserARealmAndATokenID() {
        #expect(ProxmoxConsoleAccess.identities(fromTokenValue: "test-user@pam!test-token=s")! == ("test-user@pam", "test-user@pam!test-token"))
        #expect(ProxmoxConsoleAccess.identities(fromTokenValue: "test-user@pam=s") == nil)
        #expect(ProxmoxConsoleAccess.identities(fromTokenValue: "test-userpam!test-token=s") == nil)
        #expect(ProxmoxConsoleAccess.identities(fromTokenValue: "test-user@pam!=s") == nil)
        #expect(ProxmoxConsoleAccess.identities(fromTokenValue: "no-equal") == nil)
    }
}
