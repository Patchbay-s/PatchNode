import Foundation
import LocalAuthentication
import PatchNodeCore
import Observation

@Observable
@MainActor
final class AppLockController {
    enum State: Equatable {
        case locked
        case authenticating
        case unlocked
        case failed(String)
    }

    private(set) var state: State = .locked
    /// No passcode on the device: nothing can protect the user's services, so
    /// only the demo is offered.
    private(set) var authenticationUnavailable = false
    /// Unlocked without authentication, for the demo only (no passcode set).
    private(set) var isDemoOnly = false

    /// Last successful Face ID / passcode check (unlock or action confirmation).
    private(set) var lastAuthenticatedAt: Date?
    /// Actions that change a state need an authentication younger than this.
    static let actionAuthenticationMaxAge: TimeInterval = 5 * 60

    /// Set when the app locks (launch or background) so the next return to the
    /// foreground prompts automatically once. Cleared as soon as that prompt starts,
    /// so cancelling Face ID never re-triggers the prompt in a loop: the user retries
    /// explicitly from the lock screen.
    private var shouldPromptOnActivation = true
    /// Background reached while Face ID was evaluating: the pending result must not unlock.
    private var lockRequestedDuringAuthentication = false
    private var currentContext: LAContext?

    func lockImmediately() {
        // Locking ends the 5-minute action window and any pending Face ID prompt.
        lastAuthenticatedAt = nil
        isDemoOnly = false
        if state != .authenticating {
            currentContext?.invalidate()
        }
        if state == .authenticating {
            lockRequestedDuringAuthentication = true
            currentContext?.invalidate()
            return
        }
        state = .locked
        shouldPromptOnActivation = true
    }

    /// Called whenever the scene becomes active.
    func sceneDidBecomeActive() async {
        guard shouldPromptOnActivation else { return }
        shouldPromptOnActivation = false
        await unlock()
    }

    /// Explicit retry from the lock screen.
    func unlock() async {
        guard state != .unlocked, state != .authenticating else { return }
        state = .authenticating
        // .deviceOwnerAuthentication: Face ID with automatic device passcode fallback.
        let context = LAContext()
        currentContext = context
        lockRequestedDuringAuthentication = false
        defer { currentContext = nil }
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            authenticationUnavailable = evalError?.code == LAError.Code.passcodeNotSet.rawValue
            state = .failed(authenticationUnavailable
                ? String(localized: "Set a passcode on this iPhone to use PatchNode with your services. You can explore the demo meanwhile.")
                : String(localized: "Face ID / passcode authentication is unavailable on this device."))
            return
        }
        authenticationUnavailable = false
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock PatchNode")
            )
            state = success ? .unlocked : .locked
        } catch {
            state = .locked
        }
        if lockRequestedDuringAuthentication {
            lockRequestedDuringAuthentication = false
            state = .locked
            shouldPromptOnActivation = true
        }
        // Only an unlock that stood counts for the 5-minute action window.
        if state == .unlocked { lastAuthenticatedAt = .now }
    }

    /// No passcode set: opens the app for the demo only. Leaving the demo locks
    /// it again (the caller turns demo mode on first).
    func unlockForDemo() {
        guard authenticationUnavailable, state != .unlocked else { return }
        // Requests of the user's services from an earlier session must not be
        // readable in Diagnostics without authentication.
        RequestLog.shared.clear()
        isDemoOnly = true
        lastAuthenticatedAt = nil
        state = .unlocked
    }

    /// Before an action that changes a state: asks for Face ID / passcode again if
    /// the last authentication is older than 5 minutes (`alwaysAsk`: every time,
    /// for where the tokens are stored). Returns false if refused.
    func authenticateForAction(reason: String, alwaysAsk: Bool = false) async -> Bool {
        guard state == .unlocked else { return false }
        // Demo-only session: every service is a demo one, actions are simulated.
        if isDemoOnly { return DemoMode.isOn }
        if !alwaysAsk, let lastAuthenticatedAt, Date.now.timeIntervalSince(lastAuthenticatedAt) < Self.actionAuthenticationMaxAge {
            return true
        }
        let context = LAContext()
        currentContext = context
        defer { if currentContext === context { currentContext = nil } }
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else { return false }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            // Locked (backgrounded) meanwhile: the action must not run.
            guard success, state == .unlocked else { return false }
            lastAuthenticatedAt = .now
            return true
        } catch {
            return false
        }
    }
}
