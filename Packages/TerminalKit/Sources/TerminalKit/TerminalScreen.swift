#if canImport(UIKit)
import UIKit
import SwiftUI
@preconcurrency import SwiftTerm
import PatchNodeCore

/// One terminal on screen: a SwiftTerm view kept alive for its session (the
/// scrollback survives switching tabs), its colors and font. Bytes in and
/// out only; nothing is recorded.
///
/// From the remote side: links are never opened, OSC 52 clipboard writes are
/// ignored (a server must not fill the clipboard).
@MainActor
public final class TerminalScreen: NSObject {
    public let view: TerminalView
    private var apcFilter = APCFilter()
    /// What the user types (keyboard, key bar, paste).
    public var onInput: (([UInt8]) -> Void)?
    /// The visible size changed (rotation, Split View, window resize, font).
    public var onResize: ((TerminalSize) -> Void)?
    /// The remote side set a title (OSC 0/2), kept short.
    public var onTitle: ((String) -> Void)?

    public private(set) var size: TerminalSize = .standard
    public private(set) var fontSize: Double

    public init(fontSize: Double = TerminalPreferences.fontSize()) {
        self.fontSize = fontSize
        view = LocalCopyTerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        super.init()
        view.terminalDelegate = self
        view.optionAsMetaKey = true
        view.allowMouseReporting = false
        view.font = Self.font(size: fontSize)
        // Memory: up to 8 sessions; an iPhone keeps less history.
        view.getTerminal().changeHistorySize(UIDevice.current.userInterfaceIdiom == .phone ? 2000 : 5000)
        applyPalette(for: view.traitCollection.userInterfaceStyle)
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (terminal: TerminalView, _: UITraitCollection) in
            self?.applyPalette(for: terminal.traitCollection.userInterfaceStyle)
        }
    }

    /// Remote output, without APC sequences (Kitty graphics file reads).
    public func feed(_ bytes: [UInt8]) {
        let filtered = apcFilter.filter(bytes)
        guard !filtered.isEmpty else { return }
        view.feed(byteArray: filtered[...])
    }

    /// A local message (connection state), dimmed, on its own line.
    public func showNotice(_ text: String) {
        view.feed(text: "\r\n\u{1B}[2m\(text)\u{1B}[0m\r\n")
    }

    public func setFontSize(_ size: Double) {
        let clamped = TerminalPreferences.clamped(size)
        guard clamped != fontSize else { return }
        fontSize = clamped
        TerminalPreferences.setFontSize(clamped)
        view.font = Self.font(size: clamped)
    }

    public func copySelection() {
        view.copy(nil)
    }

    public func paste() {
        view.paste(nil)
    }

    public func focus() {
        _ = view.becomeFirstResponder()
    }

    private func applyPalette(for style: UIUserInterfaceStyle) {
        let palette: TerminalPalette = style == .dark ? .dark : .light
        view.installColors(palette.ansi.map(Self.color))
        view.nativeForegroundColor = Self.uiColor(palette.foreground)
        view.nativeBackgroundColor = Self.uiColor(palette.background)
        view.backgroundColor = Self.uiColor(palette.background)
        view.caretColor = .tintColor
        view.selectedTextBackgroundColor = UIColor.tintColor.withAlphaComponent(0.35)
        view.keyboardAppearance = style == .dark ? .dark : .light
    }

    private static func font(size: Double) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func color(_ rgb: TerminalPalette.RGB) -> SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(rgb.red) * 257, green: UInt16(rgb.green) * 257, blue: UInt16(rgb.blue) * 257)
    }

    private static func uiColor(_ rgb: TerminalPalette.RGB) -> UIColor {
        UIColor(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

extension TerminalScreen: @MainActor TerminalViewDelegate {
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        let new = TerminalSize(columns: newCols, rows: newRows)
        guard new != size else { return }
        size = new
        onResize?(new)
    }

    public func setTerminalTitle(source: TerminalView, title: String) {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(60))
        onTitle?(String(scalars))
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Array(data))
    }

    public func scrolled(source: TerminalView, position: Double) {}

    /// Never opened from here: a remote program could point anywhere.
    public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

    public func bell(source: TerminalView) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// OSC 52: ignored, the clipboard is the user's.
    public func clipboardCopy(source: TerminalView, content: Data) {}

    public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Copies stay on this device and expire: what a terminal shows (a `.env`,
/// a key) never goes to the Universal Clipboard.
final class LocalCopyTerminalView: TerminalView {
    @objc override func copy(_ sender: Any?) {
        guard let text = getSelection(), !text.isEmpty else { return }
        LocalPasteboard.copy(text)
        selectNone()
    }
}

public enum LocalPasteboard {
    public static let lifetime: TimeInterval = 120

    @MainActor
    public static func copy(_ text: String) {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: text]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(lifetime)]
        )
    }
}

/// Hosts a `TerminalScreen`'s view in SwiftUI. The same view is reused when
/// SwiftUI rebuilds the hierarchy, so the scrollback stays.
public struct TerminalSurface: UIViewRepresentable {
    let screen: TerminalScreen
    let focused: Bool

    public init(screen: TerminalScreen, focused: Bool = true) {
        self.screen = screen
        self.focused = focused
    }

    public func makeUIView(context: Context) -> TerminalContainer {
        TerminalContainer(terminal: screen.view)
    }

    public func updateUIView(_ container: TerminalContainer, context: Context) {
        container.attach(screen.view)
        if focused, container.window != nil, !screen.view.isFirstResponder {
            screen.focus()
        }
    }

    public static func dismantleUIView(_ container: TerminalContainer, coordinator: ()) {
        // The terminal view belongs to its session: only detached here.
        container.detach()
    }
}

/// Plain container: the terminal view fills it and moves between containers
/// when SwiftUI recreates them.
public final class TerminalContainer: UIView {
    init(terminal: TerminalView) {
        super.init(frame: .zero)
        attach(terminal)
    }

    required init?(coder: NSCoder) { nil }

    func attach(_ terminal: TerminalView) {
        guard terminal.superview !== self else { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func detach() {
        subviews.forEach { $0.removeFromSuperview() }
    }
}
#endif
