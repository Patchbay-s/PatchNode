import Foundation
import Testing
import PatchNodeCore
@testable import RemoteAccessKit

@Suite("termproxy protocol")
struct TermProxyProtocolTests {
    @Test func handshakeIsUserColonTicketNewline() {
        #expect(TermProxyProtocol.handshake(user: "test-user@pam!test-token", ticket: "PVEVNC:x") == Data("test-user@pam!test-token:PVEVNC:x\n".utf8))
    }

    @Test func inputLengthCountsBytesNotCharacters() {
        #expect(TermProxyProtocol.input(Array("ls\r".utf8)) == Data("0:3:ls\r".utf8))
        let accented = Array("é".utf8)
        #expect(TermProxyProtocol.input(accented) == Data("0:2:".utf8) + Data(accented))
    }

    @Test func resizeAndKeepAlive() {
        #expect(TermProxyProtocol.resize(columns: 120, rows: 40) == Data("1:120:40:".utf8))
        #expect(TermProxyProtocol.keepAlive == Data("2".utf8))
    }

    @Test func acceptanceAndTrailingOutput() {
        #expect(TermProxyProtocol.isAccepted(Data("OK".utf8)))
        #expect(!TermProxyProtocol.isAccepted(Data("NO".utf8)))
        #expect(TermProxyProtocol.outputAfterAcceptance(Data("OKlogin: ".utf8)) == Data("login: ".utf8))
    }
}

@Suite("Console failures")
struct ConsoleFailureTests {
    @Test func upgradeStatusesMapToReasons() {
        #expect(ConsoleFailure.fromUpgradeStatus(401) == .tokenRefused)
        #expect(ConsoleFailure.fromUpgradeStatus(403) == .missingPrivilege)
        #expect(ConsoleFailure.fromUpgradeStatus(502) == .server(502))
        #expect(ConsoleFailure.fromUpgradeStatus(nil) == .unreachable)
    }

    @Test func codesAreShortAndStable() {
        #expect(ConsoleFailure.tokenRefused.code == "pve-token-refused")
        #expect(ConsoleFailure.server(500).code == "pve-http-500")
        #expect(ConsoleFailure(ServiceProviderError.forbidden) == .missingPrivilege)
    }

    @Test func websocketRefusesAnythingButWss() {
        #expect(throws: ConsoleFailure.unreachable) {
            _ = try ConsoleWebSocket(url: URL(string: "ws://proxmox.example.invalid/x")!, headers: [:])
        }
    }
}

@Suite("Embedded noVNC")
struct NoVNCResourcesTests {
    @Test func theBridgeAndNoVNCAreBundled() throws {
        let directory = try #require(NoVNCResources.directory)
        for path in ["index.html", "PatchNode.js", "core/rfb.js", "core/websock.js", "vendor/pako/lib/zlib/inflate.js", "licenses/LICENSE.MPL-2.0", "VERSION.txt"] {
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: path).path(percentEncoded: false)), "\(path)")
        }
    }

    @Test func thePageCannotReachTheNetwork() throws {
        let directory = try #require(NoVNCResources.directory)
        let html = try String(contentsOf: directory.appending(path: "index.html"), encoding: .utf8)
        #expect(html.contains("connect-src 'none'"))
        #expect(html.contains("default-src 'none'"))
        let bridge = try String(contentsOf: directory.appending(path: "PatchNode.js"), encoding: .utf8)
        #expect(!bridge.contains("new WebSocket"))
        #expect(!bridge.contains("fetch("))
    }

    @Test func schemeHandlerStaysInsideTheFolder() throws {
        let directory = try #require(NoVNCResources.directory)
        #expect(NoVNCResources.file(forPath: "/core/rfb.js", in: directory) != nil)
        #expect(NoVNCResources.file(forPath: "/../noVNC/index.html", in: directory) == nil)
        #expect(NoVNCResources.file(forPath: "/core/../../Info.plist", in: directory) == nil)
        #expect(NoVNCResources.file(forPath: "/", in: directory) == nil)
        #expect(NoVNCResources.mimeType(for: URL(fileURLWithPath: "/x/rfb.js")) == "text/javascript")
    }
}

@Suite("Proxmox commands over SSH")
struct ProxmoxSSHCommandsTests {
    @Test func enterContainerUsesSudoUnlessRoot() {
        #expect(ProxmoxSSHCommands.enterContainer(vmid: 101, user: "root") == "pct enter 101")
        #expect(ProxmoxSSHCommands.enterContainer(vmid: 101, user: "patchnode") == "sudo pct enter 101")
        #expect(ProxmoxSSHCommands.enterContainer(vmid: 0, user: "root") == nil)
    }
}
