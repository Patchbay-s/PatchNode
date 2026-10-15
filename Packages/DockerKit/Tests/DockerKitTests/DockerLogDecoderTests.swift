import Foundation
import Testing
@testable import DockerKit

private typealias F = DockerFixtures

/// 2024-05-01T10:00:00Z
private let may1At10 = Date(timeIntervalSince1970: 1_714_557_600)

private func decode(_ bytes: [UInt8], timestamps: Bool = false) -> [DockerLogLine] {
    DockerLogDecoder.decode(Data(bytes), timestamps: timestamps)
}

@Suite struct DockerLogDecoderTests {
    // MARK: Multiplexed framing

    @Test func multiplexedStdoutAndStderrFramesAreSeparated() {
        let body = F.frame(1, "listening on :8080\n")
            + F.frame(2, "WARN cache miss\n")
            + F.frame(1, "GET /health 200\nGET /metrics 200\n")
        let lines = decode(body)
        #expect(lines.map(\.text) == ["listening on :8080", "WARN cache miss", "GET /health 200", "GET /metrics 200"])
        #expect(lines.map(\.stream) == [.stdout, .stderr, .stdout, .stdout])
        #expect(lines.allSatisfy { $0.timestamp == nil })
    }

    @Test func stdinStreamZeroIsTreatedAsStdout() {
        let lines = decode(F.frame(0, "from stdin\n"))
        #expect(lines.map(\.stream) == [.stdout])
        #expect(lines.map(\.text) == ["from stdin"])
    }

    @Test func frameLargerThan255BytesUsesBigEndianSize() {
        // 300 = 0x0000012C, written explicitly (not via the helper).
        let payload = Array(repeating: UInt8(ascii: "a"), count: 299) + [UInt8(ascii: "\n")]
        let body: [UInt8] = [1, 0, 0, 0, 0x00, 0x00, 0x01, 0x2C] + payload + F.frame(2, "after\n")
        let lines = decode(body)
        #expect(lines.count == 2)
        #expect(lines.first?.text == String(repeating: "a", count: 299))
        #expect(lines.last?.text == "after")
        #expect(lines.last?.stream == .stderr)
    }

    @Test func frameLargerThan65535BytesUsesBigEndianSize() {
        // 70_000 = 0x00011170.
        let payload = Array(repeating: UInt8(ascii: "b"), count: 69_999) + [UInt8(ascii: "\n")]
        let body: [UInt8] = [2, 0, 0, 0, 0x00, 0x01, 0x11, 0x70] + payload + F.frame(1, "next\n")
        let lines = decode(body)
        #expect(lines.count == 2)
        #expect(lines.first?.stream == .stderr)
        // The whole 70 000-byte frame was consumed (the next frame decodes), and the
        // over-long line is cut to maxLineBytes plus an ellipsis.
        #expect(lines.first?.text == String(repeating: "b", count: DockerLogDecoder.maxLineBytes) + "…")
        #expect(lines.last?.text == "next")
        #expect(lines.last?.stream == .stdout)
    }

    @Test func invisibleAndBidiCharactersAreRemoved() {
        #expect(DockerLogDecoder.clean("a\u{202E}b\u{200B}c\u{2066}d\u{FEFF}e") == "abcde")
    }

    @Test func splittingAtEveryByteOffsetGivesIdenticalOutput() {
        let body = F.frame(1, "2024-05-01T10:00:00.000000001Z first line\nsecond ")
            + F.frame(2, "2024-05-01T10:00:01Z err\n")
            + F.frame(1, "half\n")
            + F.frame(1, "2024-05-01T10:00:02+02:00 \u{1B}[31mred\u{1B}[0m\r\n")
        let reference = decode(body, timestamps: true)
        #expect(reference.count == 4)

        for split in 0...body.count {
            var decoder = DockerLogDecoder(timestamps: true)
            let lines = decoder.append(Data(body[..<split]))
                + decoder.append(Data(body[split...]))
                + decoder.finish()
            #expect(lines == reference, "split at \(split)")
        }
    }

    @Test func feedingOneByteAtATimeGivesIdenticalOutput() {
        let body = F.frame(1, "alpha\nbeta\n") + F.frame(2, "gamma\n")
        let reference = decode(body)
        var decoder = DockerLogDecoder(timestamps: false)
        var lines: [DockerLogLine] = []
        for byte in body {
            lines += decoder.append(Data([byte]))
        }
        lines += decoder.finish()
        #expect(lines == reference)
    }

    @Test func completeFramesAreReturnedBeforeFinish() {
        var decoder = DockerLogDecoder(timestamps: false)
        let first = decoder.append(Data(F.frame(1, "ready\n")))
        #expect(first.map(\.text) == ["ready"])
        #expect(decoder.finish().isEmpty)
    }

    @Test func lineSplitAcrossTwoFramesOfSameStreamIsJoined() {
        let body = F.frame(1, "hello ") + F.frame(2, "boom\n") + F.frame(1, "world\n")
        let lines = decode(body)
        #expect(lines.map(\.text) == ["boom", "hello world"])
        #expect(lines.map(\.stream) == [.stderr, .stdout])
    }

    @Test func trailingLineWithoutNewlineIsFlushedByFinish() {
        var decoder = DockerLogDecoder(timestamps: false)
        #expect(decoder.append(Data(F.frame(1, "no newline"))).isEmpty)
        let flushed = decoder.finish()
        #expect(flushed.map(\.text) == ["no newline"])
        #expect(flushed.map(\.stream) == [.stdout])
    }

    @Test func truncatedLastFrameKeepsItsBytes() {
        // Header announces 100 bytes, only 12 arrive.
        let body = F.frame(1, "complete\n") + [2, 0, 0, 0, 0, 0, 0, 100] + Array("partial line".utf8)
        let lines = decode(body)
        #expect(lines.map(\.text) == ["complete", "partial line"])
        #expect(lines.map(\.stream) == [.stdout, .stderr])
    }

    @Test func fewerThanEightTrailingBytesAreKeptAsText() {
        let body = F.frame(1, "ok\n") + Array("tail".utf8)
        let lines = decode(body)
        #expect(lines.map(\.text) == ["ok", "tail"])
    }

    @Test func corruptHeaderMidStreamSwitchesToRawWithoutLosingData() {
        let body = F.frame(1, "framed\n") + Array("garbage text\nmore garbage\n".utf8)
        let lines = decode(body)
        #expect(lines.map(\.text) == ["framed", "garbage text", "more garbage"])
        #expect(lines.map(\.stream) == [.stdout, .console, .console])
    }

    @Test func lineIDsAreSequential() {
        let body = F.frame(1, "a\nb\n") + F.frame(2, "c\n") + F.frame(1, "d")
        let lines = decode(body)
        #expect(lines.map(\.id) == [0, 1, 2, 3])
    }

    @Test func emptyBodyGivesNoLines() {
        #expect(decode([]).isEmpty)
        #expect(DockerLogDecoder.decode(Data(), timestamps: true).isEmpty)
    }

    @Test func emptyFramesAreHarmless() {
        let body = F.frame(1, "") + F.frame(1, "x\n")
        #expect(decode(body).map(\.text) == ["x"])
    }

    // MARK: Timestamps

    @Test func timestampsAreParsedAndStripped() throws {
        let body = F.frame(1, "2024-05-01T10:00:00.123456789Z server started\n")
            + F.frame(2, "2024-05-01T12:00:00+02:00 same instant with offset\n")
            + F.frame(1, "2024-05-01T10:00:00Z\n")
        let lines = decode(body, timestamps: true)
        #expect(lines.map(\.text) == ["server started", "same instant with offset", ""])
        let first = try #require(lines[0].timestamp)
        #expect(abs(first.timeIntervalSince(may1At10) - 0.123456789) < 1e-5)
        #expect(lines[1].timestamp == may1At10)
        #expect(lines[2].timestamp == may1At10)
    }

    @Test func textIsKeptWhenPrefixIsNotATimestamp() {
        let lines = decode(F.frame(1, "not-a-date hello\n"), timestamps: true)
        #expect(lines.first?.timestamp == nil)
        #expect(lines.first?.text == "not-a-date hello")
    }

    @Test func timestampsAreNotParsedWhenDisabled() {
        let lines = decode(F.frame(1, "2024-05-01T10:00:00Z hello\n"), timestamps: false)
        #expect(lines.first?.timestamp == nil)
        #expect(lines.first?.text == "2024-05-01T10:00:00Z hello")
    }

    // MARK: TTY / raw

    @Test func ttyRawStreamIsDetectedAsConsole() {
        let body = Array("2024-05-01T10:00:00.000000000Z \u{1B}[32mINFO\u{1B}[0m started\r\n2024-05-01T10:00:01.000000000Z ready\r\n".utf8)
        let lines = decode(body, timestamps: true)
        #expect(lines.map(\.stream) == [.console, .console])
        #expect(lines.map(\.text) == ["INFO started", "ready"])
        #expect(lines.first?.timestamp == may1At10)
    }

    @Test func shortRawBodyIsDecodedOnFinish() {
        #expect(decode(Array("hi\n".utf8)).map(\.text) == ["hi"])
        #expect(decode(Array("hi\n".utf8)).map(\.stream) == [.console])
    }

    @Test func crlfEndingsAreStripped() {
        let lines = decode(F.frame(1, "windows line\r\nanother\r\n"))
        #expect(lines.map(\.text) == ["windows line", "another"])
    }

    // MARK: Cleaning

    @Test func ansiColorSequencesAreRemoved() {
        let lines = decode(F.frame(1, "\u{1B}[31mERROR\u{1B}[0m disk \u{1B}[1;33mfull\u{1B}[0m\n"))
        #expect(lines.first?.text == "ERROR disk full")
    }

    @Test func oscSequencesAreRemoved() {
        #expect(DockerLogDecoder.clean("\u{1B}]0;window title\u{07}text") == "text")
        #expect(DockerLogDecoder.clean("\u{1B}]8;;https://docs.example.invalid\u{1B}\\link\u{1B}]8;;\u{1B}\\ end") == "link end")
    }

    @Test func otherControlCharactersAreRemovedButTabsKept() {
        #expect(DockerLogDecoder.clean("a\u{00}b\u{07}c\u{08}d\u{7F}e\u{85}f\tg") == "abcdef\tg")
        #expect(DockerLogDecoder.clean("dangling\u{1B}") == "dangling")
        #expect(DockerLogDecoder.clean("unterminated \u{1B}[31") == "unterminated ")
        #expect(DockerLogDecoder.clean("caf\u{E9} \u{1F433}") == "caf\u{E9} \u{1F433}")
    }

    /// `ESC ( B` (select ASCII charset, 3 bytes) is what `tput sgr0` emits on xterm
    /// (`\e(B\e[m`), so it's common in shell-script logs: no stray "B" may remain.
    @Test func charsetDesignationSequenceIsRemoved() {
        #expect(DockerLogDecoder.clean("\u{1B}(Bplain") == "plain")
        #expect(DockerLogDecoder.clean("\u{1B}(B\u{1B}[mreset") == "reset")
        #expect(DockerLogDecoder.clean("\u{1B})0line") == "line")
    }

    @Test func invalidUTF8DoesNotCrash() {
        let body = F.frame(1, [0xFF, 0xFE, UInt8(ascii: "A"), 0xC3, UInt8(ascii: "\n")])
            + F.frame(1, [0xE2, 0x82]) // truncated multi-byte sequence at the end
        let lines = decode(body)
        #expect(lines.count == 2)
        #expect(lines.first?.text.contains("A") == true)
    }

    @Test func invalidUTF8RawStreamDoesNotCrash() {
        let lines = decode([0xC0, 0xC1, 0xF5, 0xFF, 0x41, 0x42, 0x43, 0x44, 0x0A], timestamps: true)
        #expect(lines.count == 1)
        #expect(lines.first?.text.hasSuffix("ABCD") == true)
    }
}

@Suite struct DockerTimestampTests {
    @Test func parsesNanosecondsInUTC() throws {
        let date = try #require(DockerTimestamp.parse("2024-05-01T10:00:00.123456789Z"))
        #expect(abs(date.timeIntervalSince(may1At10) - 0.123456789) < 1e-5)
    }

    @Test func parsesWithoutFraction() {
        #expect(DockerTimestamp.parse("2024-05-01T10:00:00Z") == may1At10)
        #expect(DockerTimestamp.parse("2024-05-01t10:00:00z") == may1At10)
    }

    @Test func parsesOffsets() {
        #expect(DockerTimestamp.parse("2024-05-01T12:00:00+02:00") == may1At10)
        #expect(DockerTimestamp.parse("2024-05-01T05:30:00-04:30") == may1At10)
        let withFraction = DockerTimestamp.parse("2024-05-01T12:00:00.5+02:00")
        #expect(withFraction == may1At10.addingTimeInterval(0.5))
    }

    @Test func parsesZeroDate() throws {
        let date = try #require(DockerTimestamp.parse("0001-01-01T00:00:00Z"))
        #expect(date.timeIntervalSince1970 < 0)
    }

    @Test func parsesSubstring() {
        let line = "2024-05-01T10:00:00Z message"
        #expect(DockerTimestamp.parse(line.prefix(20)) == may1At10)
    }

    @Test(arguments: [
        "",
        "not a date",
        "2024-05-01",
        "2024-05-01T10:00:00",          // no zone
        "2024-05-01 10:00:00Z",         // space instead of T
        "2024/05/01T10:00:00Z",
        "2024-05-01T10:00:00.Z",        // empty fraction
        "2024-05-01T10:00:00+0200",     // offset without colon
        "2024-05-01T10:00:00+02",
        "2024-05-01T10:00:00Zjunk",
        "2024-05-01T10:00:00Z ",
        "2024-05-01T1a:00:00Z",
        "２０２４-05-01T10:00:00Z",       // non-ASCII digits
        "2024-05-01T10:00:00+02:00x",
    ])
    func invalidStringsReturnNil(text: String) {
        #expect(DockerTimestamp.parse(text) == nil)
    }

    /// `Calendar.date(from:)` would roll these over (month 13 → January next year);
    /// they must be rejected instead.
    @Test(arguments: ["2024-13-01T10:00:00Z", "2024-02-30T10:00:00Z", "2024-05-01T25:00:00Z", "2024-05-01T10:61:00Z"])
    func outOfRangeComponentsReturnNil(text: String) {
        #expect(DockerTimestamp.parse(text) == nil)
    }
}
