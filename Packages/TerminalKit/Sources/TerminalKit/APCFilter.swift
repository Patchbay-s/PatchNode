import Foundation

/// Removes Kitty graphics commands from remote output before SwiftTerm
/// parses it: their file transmissions (`t=f`, `t=t`, `t=s`) would let a
/// server make the app read files of its own container, and SwiftTerm has
/// no switch to turn them off.
///
/// Independent of the parser's state, on purpose (an earlier filter that
/// tracked states could be bypassed): SwiftTerm 1.10.1 (`EscapeSequenceParser`)
/// can only start an APC with ESC (followed by control bytes it executes
/// while staying in its escape state: 0x00–0x18, 0x1C–0x1F, DEL) then `_`,
/// or with the C1 byte 0x9F; it skips control bytes inside it, and runs
/// Kitty graphics only when the content starts with `G`. So wherever such a start is followed
/// (after skipped bytes) by `G`, everything is dropped up to a byte that
/// ends an APC for SwiftTerm (ESC, BEL, CAN, SUB, ST 0x9C) — with no length
/// limit, or the rest would reach SwiftTerm still inside the APC. Anything
/// else passes unchanged (other APCs are ignored by SwiftTerm). Rare false
/// positive: a UTF-8 character ending in 0x9F right before `G`. Stateful
/// across chunks.
public struct APCFilter: Sendable {
    private enum State: Sendable {
        case text
        /// ESC and the control bytes after it, held until the next byte.
        case escape([UInt8])
        /// A possible APC start and the skipped bytes after it, held.
        case candidate([UInt8])
        /// Inside a Kitty command: dropped.
        case dropping
        /// ESC ending a dropped command: `\` completes ST (dropped too);
        /// anything else is read as after an ESC (a new `_` + `G` is caught).
        case droppingEscape
    }

    private var state = State.text

    public init() {}

    /// Wider than SwiftTerm's own rules (dropping too much is safe).
    static func isSkippedInAPC(_ byte: UInt8) -> Bool {
        byte <= 0x19 || (0x1C...0x20).contains(byte)
    }

    /// Bytes SwiftTerm executes or ignores after ESC without leaving its
    /// escape state (a later `_` still starts an APC).
    static func keepsEscapeState(_ byte: UInt8) -> Bool {
        byte <= 0x19 || (0x1C...0x1F).contains(byte) || byte == 0x7F
    }

    /// Held bytes are bounded: beyond this, more skipped bytes are dropped
    /// (they only affect display, never what the parser does next).
    static let maxHeld = 64

    private static func holding(_ held: [UInt8], _ byte: UInt8) -> [UInt8] {
        held.count < maxHeld ? held + [byte] : held
    }

    public mutating func filter(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        for byte in input { step(byte, into: &output) }
        return output
    }

    private mutating func step(_ byte: UInt8, into output: inout [UInt8]) {
        switch state {
        case .text:
            switch byte {
            case 0x1B: state = .escape([0x1B])
            case 0x9F: state = .candidate([0x9F])
            default: output.append(byte)
            }

        case .escape(let held):
            if byte == 0x5F {
                state = .candidate(Self.holding(held, byte))
            } else if byte == 0x1B {
                output += held                                  // a new ESC restarts it
                state = .escape([0x1B])
            } else if byte == 0x9F {
                output += held
                state = .candidate([0x9F])
            } else if Self.keepsEscapeState(byte) {
                state = .escape(Self.holding(held, byte))
            } else {
                output += held
                output.append(byte)
                state = .text
            }

        case .candidate(var held):
            if byte == 0x47 {                                   // G: Kitty graphics
                state = .dropping
            } else if Self.isSkippedInAPC(byte) {
                if held.count < Self.maxHeld { held.append(byte) }
                state = .candidate(held)
            } else if byte == 0x9F {
                output += held                                  // an empty APC, harmless
                state = .candidate([0x9F])
            } else if byte == 0x1B {
                output += held
                state = .escape([0x1B])
            } else {
                output += held
                output.append(byte)
                state = .text
            }

        case .dropping:
            switch byte {
            case 0x1B: state = .droppingEscape
            case 0x07, 0x18, 0x1A, 0x9C: state = .text
            default: break
            }

        case .droppingEscape:
            if byte == 0x5C {
                state = .text
            } else {
                state = .escape([])
                step(byte, into: &output)
            }
        }
    }
}
