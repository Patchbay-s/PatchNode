import SwiftUI

extension View {
    /// Runs `action` immediately, then every `seconds`, only while this view is on
    /// screen and the app is in the foreground. `.task` cancels the loop when the
    /// view disappears (tab switch, navigation, lock) or the scene leaves the
    /// screen (`ScenePhase.isOnScreen`: on the Mac, a window behind another app
    /// keeps refreshing).
    func polling(every seconds: Int, _ action: @escaping () async -> Void) -> some View {
        modifier(PollingModifier(seconds: seconds, action: action))
    }
}

private struct PollingModifier: ViewModifier {
    let seconds: Int
    let action: () async -> Void
    @Environment(\.scenePhase) private var scenePhase

    private struct Key: Hashable {
        let isActive: Bool
        let seconds: Int
    }

    func body(content: Content) -> some View {
        content.task(id: Key(isActive: scenePhase.isOnScreen, seconds: seconds)) {
            guard scenePhase.isOnScreen else { return }
            while !Task.isCancelled {
                await action()
                try? await Task.sleep(for: .seconds(max(seconds, 10)))
            }
        }
    }
}

extension View {
    /// Extra room under a tab's scrolling content so the floating tab bar never
    /// covers the last row (seen on iPhone in the Proxmox list).
    func tabBarClearance() -> some View {
        contentMargins(.bottom, 56, for: .scrollContent)
    }
}
