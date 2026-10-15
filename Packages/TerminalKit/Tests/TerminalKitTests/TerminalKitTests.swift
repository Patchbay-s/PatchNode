import Foundation
import Testing
import PatchNodeCore
@testable import TerminalKit

@Suite("Terminal palettes")
struct TerminalPaletteTests {
    @Test func lightPaletteIsReadableOnItsBackground() {
        let palette = TerminalPalette.light
        #expect(TerminalPalette.contrast(palette.foreground, palette.background) >= 7)
        // ANSI white and bright white included: nothing vanishes on white.
        for color in palette.ansi {
            #expect(TerminalPalette.contrast(color, palette.background) >= 3, "\(color)")
        }
    }

    @Test func darkPaletteIsReadableOnItsBackground() {
        let palette = TerminalPalette.dark
        #expect(TerminalPalette.contrast(palette.foreground, palette.background) >= 7)
        // ANSI black is the background's neighbour by design; the others read.
        for color in palette.ansi.dropFirst() where color != palette.ansi[8] {
            #expect(TerminalPalette.contrast(color, palette.background) >= 3, "\(color)")
        }
    }

    @Test func bothPalettesHaveSixteenColors() {
        #expect(TerminalPalette.light.ansi.count == 16)
        #expect(TerminalPalette.dark.ansi.count == 16)
    }
}

@Suite("Terminal preferences")
struct TerminalPreferencesTests {
    @Test func fontSizeIsClampedAndDefaulted() throws {
        let defaults = try #require(UserDefaults(suiteName: "TerminalPreferencesTests-\(UUID())"))
        #expect(TerminalPreferences.fontSize(defaults) == TerminalPreferences.defaultFontSize)
        TerminalPreferences.setFontSize(99, defaults)
        #expect(TerminalPreferences.fontSize(defaults) == TerminalPreferences.fontSizes.upperBound)
        TerminalPreferences.setFontSize(1, defaults)
        #expect(TerminalPreferences.fontSize(defaults) == TerminalPreferences.fontSizes.lowerBound)
    }
}

@Suite("Demo terminal")
struct DemoTerminalTests {
    private func collect(_ channel: any TerminalChannel, until marker: String) async throws -> String {
        var text = ""
        for try await chunk in channel.output {
            text += String(decoding: chunk, as: UTF8.self)
            if text.contains(marker) { break }
        }
        return text
    }

    @Test func showsBannerAndPrompt() async throws {
        let channel = try await DemoTerminalConnector(hostname: "node-a", banner: "Demo console").open(size: .standard)
        let text = try await collect(channel, until: "# ")
        #expect(text.contains("Demo console"))
        #expect(text.contains("root@node-a:~# "))
    }

    @Test func echoesAndAnswersACommand() async throws {
        let channel = try await DemoTerminalConnector(hostname: "node-a", banner: "x").open(size: .standard)
        await channel.send(Array("hostnamf".utf8) + [127] + Array("e\r".utf8))
        let text = try await collect(channel, until: "node-a\r\n")
        #expect(text.contains("hostnamf"))  // echoed as typed, then erased
        #expect(text.contains("\u{8} \u{8}"))
    }

    @Test func exitEndsTheSession() async throws {
        let channel = try await DemoTerminalConnector(hostname: "node-a", banner: "x").open(size: .standard)
        await channel.send(Array("exit\r".utf8))
        var text = ""
        for try await chunk in channel.output { text += String(decoding: chunk, as: UTF8.self) }
        #expect(text.contains("logout"))
    }

    @Test func unknownCommandsAreSimulatedNotRun() {
        #expect(DemoTerminalChannel.reply(to: "rm -rf /", hostname: "x").contains("simulated"))
    }
}

@Suite("Terminal size")
struct TerminalSizeTests {
    @Test func neverBelowAMinimum() {
        let size = TerminalSize(columns: 3, rows: 1)
        #expect(size.columns == 20)
        #expect(size.rows == 5)
    }
}

@Suite("APC filter (Kitty graphics file reads)")
struct APCFilterTests {
    static let payload: [UInt8] = Array("Gt=f;eA==".utf8)
    static let attacks: [[UInt8]] = [
        [0x1B, 0x5B, 0x9F] + payload + [0x07],                    // after ESC [
        Array("\u{1B}]0;t".utf8) + [0x9F] + payload + [0x9C],     // inside an OSC
        [0x9F, 0x20, 0x09, 0x00] + payload + [0x9C],              // skipped bytes before G
        [0x1B, 0x5F, 0x1C] + payload + [0x1B, 0x5C],              // ESC _ then a skipped byte
        [0x1B, 0x1B, 0x5F] + payload + [0x07],                    // doubled ESC
        [0x1B, 0x5F] + payload + [0x1B, 0x5F] + payload + [0x07],  // a second one right after
        [0x1B, 0x00, 0x7F, 0x08, 0x5F] + payload + [0x07],        // controls between ESC and _
        [0x1B, 0x18, 0x5F] + payload + [0x07],                    // CAN kept in escape state
    ]

    @Test func heldBytesAreBounded() {
        var filter = APCFilter()
        let spaces = [UInt8](repeating: 0x20, count: 1 << 20)
        #expect(filter.filter([0x9F] + spaces).isEmpty)
        #expect(filter.filter(Self.payload + [0x07, 0x41]) == [0x41])
        var other = APCFilter()
        let controls = [UInt8](repeating: 0x00, count: 1 << 20)
        let out = other.filter([0x1B] + controls + [0x5F] + Self.payload + [0x07, 0x42])
        #expect(out == [0x42])
    }

    private func kitty(_ text: String) -> [UInt8] { Array(text.utf8) }

    @Test func dropsKittyCommandsEvenAcrossChunks() {
        var filter = APCFilter()
        #expect(filter.filter(kitty("ok\u{1B}_Gt=f,a=T;L2V0Yy9ob3N0cw==")) == kitty("ok"))
        #expect(filter.filter(kitty("\u{1B}\\after")) == kitty("after"))
    }

    @Test(arguments: APCFilterTests.attacks)
    func everyKittyStartIsRemoved(input: [UInt8]) {
        var filter = APCFilter()
        let out = filter.filter(input)
        #expect(!String(decoding: out, as: UTF8.self).contains("Gt="))
    }

    @Test func splitBetweenTheStartAndG() {
        var filter = APCFilter()
        #expect(filter.filter([0x41, 0x9F]) == [0x41])
        #expect(filter.filter([0x20]) == [])
        #expect(filter.filter(kitty("Gt=f;eA==")) == [])
        #expect(filter.filter([0x07, 0x42]) == [0x42])
    }

    @Test func aHugePayloadIsDroppedToTheEnd() {
        var filter = APCFilter()
        let payload = [UInt8](repeating: 0x41, count: 3 << 20)
        let out = filter.filter(kitty("\u{1B}_Gt=f;") + payload + kitty("\u{1B}\\done"))
        #expect(out == kitty("done"))
    }

    @Test func keepsOtherSequencesAndUTF8() {
        var filter = APCFilter()
        let colored = kitty("\u{1B}[31mred\u{1B}[0m \u{1B}]0;title\u{07} hi 😀 ok")
        #expect(filter.filter(colored) == colored)
        let otherAPC = kitty("\u{1B}_Xdata\u{1B}\\")
        #expect(filter.filter(otherAPC) == otherAPC)
        // An ESC at the end of a chunk is held, then emitted.
        #expect(filter.filter([0x41, 0x1B]) == [0x41])
        #expect(filter.filter(kitty("[1m")) == [0x1B] + kitty("[1m"))
    }
}
