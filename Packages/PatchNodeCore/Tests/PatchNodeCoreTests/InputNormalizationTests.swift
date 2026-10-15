import Foundation
import Testing
@testable import PatchNodeCore

// BUGS.md MOYEN: token and URL fields must drop what a paste adds at the ends.
@Suite("Input normalization")
struct InputNormalizationTests {
    @Test(arguments: [
        ("test-user@pam!test-token=abcd", "test-user@pam!test-token=abcd"),
        ("  test-user@pam!test-token=abcd  ", "test-user@pam!test-token=abcd"),
        ("test-user@pam!test-token=abcd\n", "test-user@pam!test-token=abcd"),
        ("\r\n\ttest-user@pam!test-token=abcd\r\n", "test-user@pam!test-token=abcd"),
        ("\u{FEFF}test-user@pam!test-token=abcd\u{200B}", "test-user@pam!test-token=abcd"),
        ("\u{00A0}user:pass word\u{00A0}", "user:pass word"),
        ("   ", ""),
    ])
    func credentialIsTrimmedAtBothEndsOnly(raw: String, expected: String) {
        #expect(InputNormalization.credential(raw) == expected)
    }

    @Test func innerCharactersAreKept() {
        #expect(InputNormalization.credential("a b\tc") == "a b\tc")
    }

    @Test func urlIsTrimmedBeforeValidation() {
        #expect(InputNormalization.url(" https://proxmox.example.invalid:8006 \n") == "https://proxmox.example.invalid:8006")
        let result = validateServiceURL("\u{200B} https://proxmox.example.invalid:8006\n")
        #expect(result == .success(URL(string: "https://proxmox.example.invalid:8006")!))
    }
}
