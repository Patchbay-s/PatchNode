import Testing
@testable import PatchNodeCore

struct ServiceEditRulesTests {
    let rules = ServiceEditRules(originalName: "Test Proxmox", originalURL: "https://proxmox.example.invalid:8006")

    @Test func renameAloneNeedsNoTest() {
        #expect(!rules.requiresTest(url: "https://proxmox.example.invalid:8006", credentialEntered: false))
        #expect(rules.canSave(name: "node-2", url: "https://proxmox.example.invalid:8006", credentialEntered: false, testPassed: false))
    }

    @Test func newPathNeedsASuccessfulTest() {
        let url = "https://proxmox.example.invalid:8006/api"
        #expect(rules.requiresTest(url: url, credentialEntered: false))
        #expect(!rules.requiresNewCredential(url: url))
        #expect(!rules.canSave(name: "Test Proxmox", url: url, credentialEntered: false, testPassed: false))
        #expect(rules.canSave(name: "Test Proxmox", url: url, credentialEntered: false, testPassed: true))
    }

    @Test func newHostOrPortNeverGetsTheStoredCredential() {
        for url in ["https://node-2.example.invalid:8006", "https://proxmox.example.invalid:8007", "https://PROXMOX.example.invalid:8006"] {
            let isSameOrigin = url.hasPrefix("https://PROXMOX")
            #expect(rules.requiresNewCredential(url: url) == !isSameOrigin)
        }
        let url = "https://node-2.example.invalid:8006"
        #expect(!rules.canSave(name: "Test Proxmox", url: url, credentialEntered: false, testPassed: true))
        #expect(rules.canSave(name: "Test Proxmox", url: url, credentialEntered: true, testPassed: true))
    }

    @Test func newCredentialNeedsASuccessfulTest() {
        let url = "https://proxmox.example.invalid:8006"
        #expect(rules.requiresTest(url: url, credentialEntered: true))
        #expect(!rules.canSave(name: "Test Proxmox", url: url, credentialEntered: true, testPassed: false))
        #expect(rules.canSave(name: "Test Proxmox", url: url, credentialEntered: true, testPassed: true))
    }

    @Test func nothingChangedOrEmptyNameCannotBeSaved() {
        let url = "https://proxmox.example.invalid:8006"
        #expect(!rules.canSave(name: "Test Proxmox", url: url, credentialEntered: false, testPassed: true))
        #expect(!rules.canSave(name: "", url: url, credentialEntered: true, testPassed: true))
    }
}

struct CredentialPairTests {
    @Test func composesUserAndPassword() {
        #expect(CredentialPair.compose(user: "monitor", password: "s3:cr:et") == .composed("monitor:s3:cr:et"))
    }

    @Test func bothEmptyIsEmpty() {
        #expect(CredentialPair.compose(user: "", password: "") == .empty)
    }

    @Test func oneFieldAloneIsIncomplete() {
        #expect(CredentialPair.compose(user: "monitor", password: "") == .incomplete)
        #expect(CredentialPair.compose(user: "", password: "secret") == .incomplete)
    }

    @Test func colonInUserIsRefused() {
        #expect(CredentialPair.compose(user: "a:b", password: "secret") == .colonInUser)
    }

    @Test func basicAuthKindsUseTwoFields() {
        #expect(ServiceKind.dockerSocketProxy.credentialShape == .pair(userIsEmail: false))
        #expect(ServiceKind.nginxProxyManager.credentialShape == .pair(userIsEmail: true))
        #expect(ServiceKind.proxmoxVE.credentialShape == .single)
        #expect(ServiceKind.tailscale.credentialShape == .single)
    }
}
