import SwiftUI
import UIKit

/// iPad and Mac ("Designed for iPad") layout: content keeps a readable width
/// instead of stretching across a 13" screen or a wide Mac window. On iPhone
/// the width is always below these limits, so nothing changes there.
enum ReadableWidth {
    /// Forms, settings, sheets, text.
    static let form: CGFloat = 720
    /// Lists of servers, containers, alerts: wider rows, still not edge to edge.
    static let data: CGFloat = 960
}

extension View {
    /// Centers the content at most `maxWidth` wide. The background fills the
    /// whole width (grouped by default, the background of `List` and `Form`).
    func readableWidth(_ maxWidth: CGFloat = ReadableWidth.form, grouped: Bool = true) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .background(grouped ? Color(.systemGroupedBackground) : Color(.systemBackground), ignoresSafeAreaEdges: .all)
    }

    /// Smallest window on the Mac, where an iPad app can be resized freely.
    /// Nothing on iPhone and iPad (Split View and Slide Over stay possible).
    func macMinimumWindowSize(_ size: CGSize = MacWindow.minimumSize) -> some View {
        background(WindowSizeRestriction(minimumSize: size).frame(width: 0, height: 0))
    }
}

extension ScenePhase {
    /// The window is visible: active, or on the Mac also inactive (another app
    /// in front, the window still on screen and no app switcher snapshot).
    var isOnScreen: Bool {
        self == .active || (MacWindow.isMac && self == .inactive)
    }
}

enum MacWindow {
    static let minimumSize = CGSize(width: 600, height: 700)

    /// A Mac window inactive this long (behind another app) locks.
    static let inactiveLockDelay = Duration.seconds(5 * 60)

    /// The iPad app running on an Apple silicon Mac.
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
}

/// Sets `UIWindowScene.sizeRestrictions` once the view is in a window.
private struct WindowSizeRestriction: UIViewRepresentable {
    let minimumSize: CGSize

    func makeUIView(context: Context) -> RestrictingView {
        RestrictingView(minimumSize: minimumSize)
    }

    func updateUIView(_ view: RestrictingView, context: Context) {}

    final class RestrictingView: UIView {
        private let minimumSize: CGSize

        init(minimumSize: CGSize) {
            self.minimumSize = minimumSize
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard MacWindow.isMac, let restrictions = window?.windowScene?.sizeRestrictions else { return }
            restrictions.minimumSize = minimumSize
        }
    }
}
