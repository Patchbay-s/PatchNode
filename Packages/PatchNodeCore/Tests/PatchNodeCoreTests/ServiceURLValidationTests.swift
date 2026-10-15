import Foundation
import Testing
@testable import PatchNodeCore

struct ServiceURLValidationTests {
    @Test func httpsURLIsAccepted() throws {
        let url = try validateServiceURL("https://proxmox.example.invalid:8006").get()
        #expect(url.scheme == "https")
        #expect(url.host == "proxmox.example.invalid")
        #expect(url.port == 8006)
    }

    @Test func uppercaseHTTPSSchemeIsAccepted() throws {
        let url = try validateServiceURL("HTTPS://proxmox.example.invalid").get()
        #expect(url.host == "proxmox.example.invalid")
    }

    @Test func httpURLIsRejectedAsNotHTTPS() {
        #expect(validateServiceURL("http://proxmox.example.invalid:8006") == .failure(.notHTTPS))
    }

    @Test(arguments: ["not a url", "https://", "", "   "])
    func malformedInputIsRejectedAsInvalidURL(raw: String) {
        #expect(validateServiceURL(raw) == .failure(.invalidURL))
    }

    @Test func surroundingWhitespaceIsTrimmed() throws {
        let url = try validateServiceURL("  \n https://grafana.example.invalid/ \t\n").get()
        #expect(url.absoluteString == "https://grafana.example.invalid/")
    }

    @Test(arguments: [
        "https://root:hunter2@proxmox.example.invalid:8006",
        "https://user@proxmox.example.invalid",
    ])
    func urlWithUserInfoIsRejectedAsContainingCredentials(raw: String) {
        #expect(validateServiceURL(raw) == .failure(.containsCredentials))
    }

    @Test(arguments: [
        "https://proxmox.example.invalid/?token=abc",
        "https://proxmox.example.invalid/#frag",
    ])
    func urlWithQueryOrFragmentIsRejectedAsInvalidURL(raw: String) {
        #expect(validateServiceURL(raw) == .failure(.invalidURL))
    }

    @Test func httpsURLWithPortAndTrailingSlashIsStillAccepted() throws {
        let url = try validateServiceURL("https://proxmox.example.invalid:8006/").get()
        #expect(url.host == "proxmox.example.invalid")
        #expect(url.port == 8006)
        #expect(url.user == nil)
        #expect(url.query == nil)
    }
}
