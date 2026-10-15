import SwiftUI

struct LockScreenView: View {
    let state: AppLockController.State
    var offersDemo = false
    let onRetry: () -> Void
    var onDemo: () -> Void = {}

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "faceid")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Unlock PatchNode")
                    .font(.headline)
                Text("Use Face ID or your passcode to unlock PatchNode.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if case .failed(let message) = state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if state != .authenticating {
                    Button("Try again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
                if offersDemo {
                    Button("Explore the demo", action: onDemo)
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}

/// Opaque cover shown whenever the scene isn't active, so the app switcher
/// snapshot never contains service names or URLs.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Covers this view whenever the scene isn't on screen. Applied to the root and to
    /// every sheet, because sheets are presented above the root's overlays.
    func privacyCover() -> some View {
        modifier(PrivacyCoverModifier())
    }
}

private struct PrivacyCoverModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if !scenePhase.isOnScreen {
                PrivacyCoverView()
            }
        }
    }
}
