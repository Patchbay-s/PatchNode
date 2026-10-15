import Foundation
import Observation
import SwiftData
import PatchNodeCore
import ProxmoxKit
import DockerKit
import ObservabilityKit
import TailscaleKit
import SecurityKit
import HomeServicesKit

@Observable
@MainActor
final class AddServiceViewModel {
    /// A new service, or an existing one edited in place (same ID, same type).
    enum Mode {
        case add
        case edit(ServiceConfig, ServiceEditRules)
    }

    enum TestResult: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var kind: ServiceKind = .proxmoxVE {
        didSet {
            // Default name follows the type until the user types their own.
            if name.isEmpty || name == oldValue.displayName { name = kind.displayName }
            invalidateTest()
        }
    }
    var name: String = ServiceKind.proxmoxVE.displayName { didSet { invalidateTest() } }
    var urlText: String = "" { didSet { invalidateTest() } }
    var token: String = "" { didSet { invalidateTest() } }
    /// Two-field credentials (`CredentialShape.pair`): composed into user:password.
    var username: String = "" { didSet { invalidateTest() } }
    var password: String = "" { didSet { invalidateTest() } }
    private(set) var testResult: TestResult = .idle
    private(set) var saveError: String?

    let mode: Mode

    var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    /// Adding: only right after a successful test with the current inputs (editing
    /// any field afterwards requires a new test). Editing: a rename alone is saved
    /// directly; a new URL or credential needs a successful test.
    var canSave: Bool {
        switch mode {
        case .add:
            return testResult == .success
        case .edit(_, let rules):
            guard urlValidationMessage == nil, credentialValidationMessage == nil else { return false }
            return rules.canSave(
                name: trimmedName, url: normalizedURLString,
                credentialEntered: credentialEntered, testPassed: testResult == .success
            )
        }
    }

    /// Editing: whether the connection must be tested again before saving.
    var requiresTest: Bool {
        switch mode {
        case .add: true
        case .edit(_, let rules): rules.requiresTest(url: normalizedURLString, credentialEntered: credentialEntered)
        }
    }

    /// Editing with a new server (scheme, host or port): the stored credential
    /// is never sent there, a new one must be typed.
    var requiresNewCredential: Bool {
        guard case .edit(_, let rules) = mode else { return false }
        return rules.requiresNewCredential(url: normalizedURLString)
    }

    /// Editing: a credential was typed, replacing the stored one on save.
    private var credentialEntered: Bool {
        kind != .uptimeKuma && !trimmedToken.isEmpty
    }

    /// The URL as it would be saved, to compare with the stored one.
    private var normalizedURLString: String {
        if case .success(let url) = validateServiceURL(effectiveURLText) { return url.absoluteString }
        return effectiveURLText
    }

    /// The URL typed, or the service's fixed public address (Tailscale).
    var effectiveURLText: String {
        kind.fixedURL?.absoluteString ?? urlText
    }

    /// Inline URL feedback while typing (HTTPS required).
    var urlValidationMessage: String? {
        guard !effectiveURLText.isEmpty else { return nil }
        switch validateServiceURL(effectiveURLText) {
        case .success(let url):
            if kind == .uptimeKuma, UptimeKumaLocation(statusPageURL: url) == nil {
                return String(localized: "Enter the status page URL, ending with /status/<slug>.")
            }
            return nil
        case .failure(.notHTTPS): return String(localized: "The URL must start with https://.")
        case .failure(.invalidURL): return String(localized: "This URL isn't valid.")
        case .failure(.containsCredentials):
            return String(localized: "Don't put a user name or password in the URL. Use the API token field.")
        }
    }

    /// Inline credential feedback: no control characters; `user:password` for the
    /// socket proxy's Basic authentication.
    var credentialValidationMessage: String? {
        let typed = kind.credentialShape == .single
            ? [trimmedToken]
            : [InputNormalization.credential(username), InputNormalization.credential(password)]
        // Control characters and invisible format characters (zero-width space, BOM…).
        if typed.contains(where: { $0.unicodeScalars.contains { [.control, .format].contains($0.properties.generalCategory) } }) {
            return String(localized: "The credential contains invalid characters (line breaks or control characters).")
        }
        if case .pair(let userIsEmail) = kind.credentialShape {
            switch composedPair {
            case .incomplete:
                return userIsEmail
                    ? String(localized: "Enter both the e-mail and the password.")
                    : String(localized: "Enter both the user name and the password.")
            case .colonInUser:
                return String(localized: "The user name can't contain “:”.")
            case .empty, .composed:
                return nil
            }
        }
        guard !trimmedToken.isEmpty else { return nil }
        switch kind {
        case .tailscale:
            // An API access token can't be scoped: it can create auth keys and change
            // ACLs, i.e. let a device into the tailnet. Already saved ones keep working.
            if trimmedToken.hasPrefix("tskey-api-") {
                return String(localized: "API access tokens have full admin rights on your tailnet. Create an OAuth client with the devices:core:read scope instead, and enter client-id:client-secret.")
            }
            if (try? TailscaleCredential(trimmedToken)) == nil {
                return String(localized: "Enter the OAuth client as client-id:client-secret.")
            }
        default:
            break
        }
        return nil
    }

    var canTest: Bool {
        // Editing: an empty credential field tests with the stored one.
        !trimmedName.isEmpty
            && (!trimmedToken.isEmpty || !kind.requiresCredential || (isEditing && !requiresNewCredential))
            && urlValidationMessage == nil && !effectiveURLText.isEmpty
            && credentialValidationMessage == nil && testResult != .testing
    }

    /// The new service's ID, or the edited one's.
    private let pendingID: UUID
    /// Called after an edit saved a new credential: the stores drop the old one.
    private let onCredentialChanged: (UUID) -> Void
    /// Identifies the in-flight test so a late answer from an older test can never
    /// mark newer, untested inputs as valid.
    private var currentTestID: UUID?
    private var testTask: Task<Void, Never>?
    private let secretStore: any SecretStore
    private let modelContext: ModelContext

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The credential to test and store: the token field, or the user and
    /// password fields composed into user:password. Spaces, line breaks and
    /// invisible characters removed at both ends (paste).
    private var trimmedToken: String {
        guard case .pair = kind.credentialShape else { return InputNormalization.credential(token) }
        if case .composed(let credential) = composedPair { return credential }
        return ""
    }

    private var composedPair: CredentialPair.Result {
        CredentialPair.compose(
            user: InputNormalization.credential(username),
            password: InputNormalization.credential(password)
        )
    }

    init(secretStore: any SecretStore, modelContext: ModelContext) {
        self.secretStore = secretStore
        self.modelContext = modelContext
        self.mode = .add
        self.pendingID = UUID()
        self.onCredentialChanged = { _ in }
    }

    /// Edits `config`: name and URL pre-filled, type fixed, credential never shown
    /// (left empty, the stored one is kept).
    init(
        editing config: ServiceConfig, secretStore: any SecretStore, modelContext: ModelContext,
        onCredentialChanged: @escaping (UUID) -> Void
    ) {
        self.secretStore = secretStore
        self.modelContext = modelContext
        self.mode = .edit(config, ServiceEditRules(originalName: config.name, originalURL: config.urlString))
        self.pendingID = config.id
        self.onCredentialChanged = onCredentialChanged
        self.kind = config.kind
        self.name = config.name
        self.urlText = config.kind.fixedURL == nil ? config.urlString : ""
    }

    /// Starts a connection test, cancelling any previous one.
    func startTest() {
        testTask?.cancel()
        testTask = Task { await testConnection() }
    }

    func cancelTest() {
        testTask?.cancel()
        testTask = nil
        currentTestID = nil
    }

    func testConnection() async {
        guard case .success(let url) = validateServiceURL(effectiveURLText) else {
            testResult = .failure(String(localized: "The URL must start with https://."))
            return
        }
        let testID = UUID()
        currentTestID = testID
        testResult = .testing
        // Editing with the credential field left empty: test the stored one.
        var credential = trimmedToken
        if credential.isEmpty, isEditing, !requiresNewCredential, kind != .uptimeKuma {
            if let origin = CredentialOrigin.of(url) {
                credential = (try? await secretStore.read(for: pendingID, origin: origin)) ?? ""
            }
            guard currentTestID == testID, !Task.isCancelled else { return }
        }
        guard !credential.isEmpty || !kind.requiresCredential else {
            currentTestID = nil
            testResult = .failure(String(localized: "The token was rejected or lacks the required rights. Check the token value and its role."))
            return
        }
        let provider = makeProvider(url: url, credential: credential)
        let status = try? await provider.healthCheck()
        // Inputs edited or a newer test started while this one was in flight: drop it.
        guard currentTestID == testID, !Task.isCancelled else { return }
        currentTestID = nil
        switch status {
        case .ok:
            testResult = .success
        case .unauthorized:
            testResult = .failure(String(localized: "The token was rejected or lacks the required rights. Check the token value and its role."))
        case .degraded(let reason) where reason == ProxmoxProvider.insufficientRightsReason:
            testResult = .failure(String(localized: "The token has no rights: untick Privilege Separation or add an API Token Permission PVEAuditor on /."))
        case .degraded(let reason):
            testResult = .failure(String(localized: "The service answered with an unexpected response (\(reason))."))
        case .unreachable(let error) where (error as? ServiceProviderError) == .blockedByProxy:
            testResult = .failure(String(localized: "Access blocked by the reverse proxy: check the VPN and the Access List (or whether CrowdSec/fail2ban banned your IP)."))
        case .unreachable, .none:
            testResult = .failure(String(localized: "The service is unreachable. Check the URL and your VPN connection."))
        }
    }

    /// Returns true when the service was saved (token in Keychain, config in SwiftData).
    func save() async -> Bool {
        saveError = nil
        guard canSave, case .success(let url) = validateServiceURL(effectiveURLText) else { return false }
        if case .edit(let config, _) = mode {
            return await saveEdit(of: config, url: url)
        }
        // Capture the tested inputs before suspending.
        let name = trimmedName
        // A status page takes no credential: never store what the hidden field kept.
        let token = kind == .uptimeKuma ? "" : trimmedToken
        do {
            // Optional credential left empty: nothing to store.
            if !token.isEmpty {
                guard let origin = CredentialOrigin.of(url) else { throw SecretStoreError.saveFailed(0) }
                try await secretStore.save(token, for: pendingID, origin: origin)
            }
        } catch {
            saveError = String(localized: "The token couldn't be stored in the Keychain.")
            return false
        }
        let config = ServiceConfig(id: pendingID, kind: kind, name: name, urlString: url.absoluteString)
        modelContext.insert(config)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(config)
            try? await secretStore.delete(for: pendingID)
            saveError = String(localized: "The service couldn't be saved.")
            return false
        }
        // The token never needs to be shown again: drop it from memory.
        self.token = ""
        username = ""
        password = ""
        return true
    }

    /// Keychain first (only after a successful test), then SwiftData; if SwiftData
    /// fails, the previous credential is put back: nothing is left half-modified.
    private func saveEdit(of config: ServiceConfig, url: URL) async -> Bool {
        let name = trimmedName
        let newCredential = credentialEntered ? trimmedToken : nil
        // Kept only for the few moments of the save, to undo it on failure.
        var previousCredential: String?
        // Each credential stays bound to its own server.
        let previousOrigin = CredentialOrigin.of(config.urlString)
        if let newCredential {
            do {
                guard let origin = CredentialOrigin.of(url) else { throw SecretStoreError.saveFailed(0) }
                if let previousOrigin {
                    previousCredential = try await secretStore.read(for: pendingID, origin: previousOrigin)
                }
                try await secretStore.save(newCredential, for: pendingID, origin: origin)
            } catch {
                saveError = String(localized: "The token couldn't be stored in the Keychain.")
                return false
            }
        }
        config.name = name
        config.urlString = url.absoluteString
        // Every copy (an iCloud sync can store a service twice).
        for copy in (try? modelContext.serviceRecords(id: config.id)) ?? [] where copy !== config {
            copy.name = name
            copy.urlString = url.absoluteString
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            if newCredential != nil {
                do {
                    if let previousCredential, let previousOrigin {
                        try await secretStore.save(previousCredential, for: pendingID, origin: previousOrigin)
                    } else {
                        try await secretStore.delete(for: pendingID)
                    }
                } catch {
                    // The new credential stayed in the Keychain next to the old URL:
                    // say so, the user enters it again.
                    saveError = String(localized: "The service couldn't be saved, and its previous credential couldn't be put back. Enter the credential again.")
                    return false
                }
            }
            saveError = String(localized: "The service couldn't be saved.")
            return false
        }
        // Same address: the stores see no configuration change and must forget
        // the old credential. A new address resets the service through
        // `configure` (calling this first would send the new credential to the
        // old address).
        if newCredential != nil, case .edit(_, let rules) = mode, rules.originalURL == url.absoluteString {
            onCredentialChanged(pendingID)
        }
        token = ""
        username = ""
        password = ""
        return true
    }

    private func makeProvider(url: URL, credential: String) -> any ServiceProvider {
        let trimmedToken = credential
        return switch kind {
        case .dockerPortainer, .dockerSocketProxy:
            DockerProvider(id: pendingID, kind: kind, displayName: trimmedName, baseURL: url, credential: trimmedToken)
        case .prometheus, .alertmanager, .grafana, .uptimeKuma:
            ObservabilityProvider(id: pendingID, kind: kind, displayName: trimmedName, baseURL: url, credential: trimmedToken)
        case .proxmoxBackupServer:
            PBSProvider(id: pendingID, displayName: trimmedName, baseURL: url, apiTokenValue: trimmedToken)
        case .tailscale:
            // Fresh cache: the test's access token is discarded with the provider.
            TailscaleProvider(id: pendingID, displayName: trimmedName, baseURL: url, credential: trimmedToken)
        case .crowdSec, .nginxProxyManager, .adGuardHome:
            SecurityProvider(id: pendingID, kind: kind, displayName: trimmedName, baseURL: url, credential: trimmedToken)
        case .homeAssistant, .glances:
            HomeServicesProvider(id: pendingID, kind: kind, displayName: trimmedName, baseURL: url, credential: trimmedToken)
        default:
            ProxmoxProvider(id: pendingID, displayName: trimmedName, baseURL: url, apiTokenValue: trimmedToken)
        }
    }

    private func invalidateTest() {
        cancelTest()
        if testResult != .idle { testResult = .idle }
    }
}
