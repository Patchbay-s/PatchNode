import SwiftUI
import UIKit
import TerminalKit

/// A plain-text editor for compose files: monospaced, line numbers in a
/// gutter, no autocorrection or smart quotes (they would break YAML).
struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> LineNumberedTextView {
        let view = LineNumberedTextView()
        view.delegate = context.coordinator
        view.setText(text)
        view.isEditable = isEditable
        return view
    }

    func updateUIView(_ view: LineNumberedTextView, context: Context) {
        if view.text != text { view.setText(text) }
        view.isEditable = isEditable
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            (textView as? LineNumberedTextView)?.textChanged()
        }
    }
}

/// TextKit 1 text view with a gutter numbering each line (not each wrapped
/// fragment). The gutter only covers the visible area and follows the
/// scroll; line starts are indexed once per edit, so drawing is cheap even
/// for a long file.
final class LineNumberedTextView: UITextView {
    let gutter = LineNumberGutter()
    static let gutterWidth: CGFloat = 44
    /// UTF-16 offset of the start of every line.
    private(set) var lineStarts: [Int] = [0]

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)
        font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize * 0.9, weight: .regular)
        adjustsFontForContentSizeCategory = true
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        inlinePredictionType = .no
        writingToolsBehavior = .none
        keyboardType = .asciiCapable
        backgroundColor = .systemBackground
        textColor = .label
        alwaysBounceVertical = true
        textContainerInset = UIEdgeInsets(top: 8, left: Self.gutterWidth + 6, bottom: 8, right: 8)
        gutter.textView = self
        gutter.isUserInteractionEnabled = false
        gutter.backgroundColor = .secondarySystemBackground
        addSubview(gutter)
    }

    required init?(coder: NSCoder) { nil }

    /// Copies stay on this device and expire (a `.env` holds secrets).
    override func copy(_ sender: Any?) {
        guard let range = selectedTextRange, let text = text(in: range), !text.isEmpty else { return }
        LocalPasteboard.copy(text)
    }

    override func cut(_ sender: Any?) {
        guard isEditable, let range = selectedTextRange, let text = text(in: range), !text.isEmpty else { return }
        LocalPasteboard.copy(text)
        replace(range, withText: "")
    }

    func setText(_ value: String) {
        text = value
        textChanged()
    }

    func textChanged() {
        let string = text as NSString
        var starts = [0]
        var index = 0
        while index < string.length {
            let range = string.range(of: "\n", options: .literal, range: NSRange(location: index, length: string.length - index))
            guard range.location != NSNotFound else { break }
            starts.append(range.location + 1)
            index = range.location + 1
        }
        lineStarts = starts
        gutter.setNeedsDisplay()
    }

    /// 1-based line holding the UTF-16 offset (binary search).
    func line(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    override var contentOffset: CGPoint {
        didSet {
            if contentOffset.y != oldValue.y { positionGutter() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionGutter()
    }

    private func positionGutter() {
        let frame = CGRect(x: 0, y: contentOffset.y, width: Self.gutterWidth, height: bounds.height)
        if gutter.frame != frame {
            gutter.frame = frame
            gutter.setNeedsDisplay()
        }
        sendSubviewToBack(gutter)
    }
}

final class LineNumberGutter: UIView {
    weak var textView: LineNumberedTextView?

    override func draw(_ rect: CGRect) {
        guard let textView, let font = textView.font else { return }
        let layout = textView.layoutManager
        let length = (textView.text as NSString).length
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: font.pointSize * 0.8, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let inset = textView.textContainerInset
        // The visible part of the text, in text-container coordinates.
        let top = frame.minY + rect.minY - inset.top
        let visible = CGRect(x: 0, y: top, width: textView.bounds.width, height: rect.height)
        func drawNumber(_ number: Int, lineRect: CGRect) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = lineRect.minY + inset.top - frame.minY + (lineRect.height - size.height) / 2
            label.draw(at: CGPoint(x: bounds.width - size.width - 6, y: y), withAttributes: attributes)
        }
        guard length > 0 else {
            drawNumber(1, lineRect: CGRect(x: 0, y: 0, width: 0, height: font.lineHeight))
            return
        }
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: textView.textContainer)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = textView.line(at: characters.location)
        let starts = textView.lineStarts
        while line - 1 < starts.count {
            let start = starts[line - 1]
            if start >= length { break }
            if start > NSMaxRange(characters) { break }
            let fragment = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: start), effectiveRange: nil)
            drawNumber(line, lineRect: fragment)
            line += 1
        }
        // The empty last line after a final newline.
        if starts.last == length, line == starts.count {
            drawNumber(line, lineRect: layout.extraLineFragmentRect)
        }
    }
}
