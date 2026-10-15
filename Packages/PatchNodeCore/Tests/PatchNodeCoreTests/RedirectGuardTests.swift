import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PatchNodeCore

struct RedirectGuardTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func sameHTTPSHostAndPortIsSameOrigin() {
        #expect(SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid:8006/api2/json/version"),
            url("https://proxmox.example.invalid:8006/api2/json/other")
        ))
    }

    @Test func implicit443AndExplicit443AreSameOrigin() {
        #expect(SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid/a"),
            url("https://proxmox.example.invalid:443/b")
        ))
        #expect(SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid:443/a"),
            url("https://proxmox.example.invalid/b")
        ))
    }

    @Test func differentHostIsNotSameOrigin() {
        #expect(!SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid/a"),
            url("https://attacker.example.invalid/a")
        ))
    }

    @Test func differentPortIsNotSameOrigin() {
        #expect(!SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid:8006/a"),
            url("https://proxmox.example.invalid:8443/a")
        ))
        #expect(!SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid/a"),
            url("https://proxmox.example.invalid:8006/a")
        ))
    }

    @Test func downgradeFromHTTPSToHTTPIsNotSameOrigin() {
        #expect(!SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid/a"),
            url("http://proxmox.example.invalid/a")
        ))
    }

    @Test func plainHTTPOriginIsNeverSameOrigin() {
        #expect(!SameOriginRedirectGuard.isSameOrigin(
            url("http://proxmox.example.invalid/a"),
            url("http://proxmox.example.invalid/b")
        ))
    }

    @Test func hostComparisonIsCaseInsensitive() {
        #expect(SameOriginRedirectGuard.isSameOrigin(
            url("https://proxmox.example.invalid:8006/a"),
            url("https://proxmox.example.invalid:8006/b")
        ))
    }

    @Test func nilURLsAreNotSameOrigin() {
        let valid = url("https://proxmox.example.invalid/a")
        #expect(!SameOriginRedirectGuard.isSameOrigin(nil, valid))
        #expect(!SameOriginRedirectGuard.isSameOrigin(valid, nil))
        #expect(!SameOriginRedirectGuard.isSameOrigin(nil, nil))
    }
}
