import SwiftUI
import WebKit
import PatchNodeCore
import RemoteAccessKit

/// A VM's graphical console: noVNC, embedded and offline, fed by a native
/// websocket. The API token never reaches the page; noVNC only gets the
/// one-time VNC password, as a JavaScript argument (never in a URL).
@Observable
@MainActor
final class GraphicalConsoleSession: WorkspaceSession {
    /// Opens the RFB stream; nil for the demo (a simulated screen).
    typealias Link = (@Sendable () async throws -> ProxmoxVNCConnection)?

    let id = UUID()
    var title: String
    let subtitle: String
    private(set) var state: SessionState = .connecting
    private(set) var failureMessage: String?
    /// Scale the remote screen to the window (else 1:1 with scrolling).
    var scalesToFit = true {
        didSet { controller?.setScale(scalesToFit) }
    }
    var isDemo: Bool { link == nil }

    @ObservationIgnored private let link: Link
    @ObservationIgnored private let logLabel: RequestLog.Label?
    @ObservationIgnored private(set) var controller: VNCWebController?
    @ObservationIgnored private var openedAt: Date?

    init(title: String, subtitle: String, link: Link, logLabel: RequestLog.Label?) {
        self.title = title
        self.subtitle = subtitle
        self.link = link
        self.logLabel = logLabel
    }

    func connect() {
        guard controller == nil else { return }
        state = .connecting
        failureMessage = nil
        guard let link else {
            // Demo: nothing to connect to.
            state = .connected
            openedAt = .now
            RequestLog.shared.append(.event(.terminalOpened(.proxmoxGraphical)), label: logLabel)
            return
        }
        let controller = VNCWebController(scale: scalesToFit) { [weak self] event in
            self?.handle(event)
        }
        self.controller = controller
        controller.start(link)
    }

    func close(reason: TerminalEndReason = .closed) {
        guard isLive else { return }
        end(reason, message: nil)
    }

    private func handle(_ event: VNCWebController.Event) {
        switch event {
        case .connected:
            guard isLive else { return }
            state = .connected
            openedAt = .now
            RequestLog.shared.append(.event(.terminalOpened(.proxmoxGraphical)), label: logLabel)
        case .title(let title):
            if !title.isEmpty { self.title = title }
        case .ended(let error):
            guard isLive else { return }
            if let error {
                end(.failed(code: (error as? any TerminalFailure)?.code ?? "error"), message: TerminalFailureText.message(for: error))
            } else {
                end(.closed, message: nil)
            }
        }
    }

    private func end(_ reason: TerminalEndReason, message: String?) {
        state = .ended(reason)
        failureMessage = message
        controller?.stop()
        controller = nil
        let duration = openedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        openedAt = nil
        RequestLog.shared.append(.event(.terminalEnded(.proxmoxGraphical, duration: duration, reason: reason)), label: logLabel)
    }
}

/// noVNC's authentication failed (ticket expired or refused).
struct VNCAuthenticationFailure: TerminalFailure {
    let code = "vnc-auth"
}

/// The web view's process stopped (memory pressure, crash).
struct VNCPageFailure: TerminalFailure {
    let code = "vnc-webcontent"
}

/// The web view, its local scheme and the bridge between the native websocket
/// and noVNC. Navigation is limited to the local scheme; the page itself has
/// no network access (Content-Security-Policy).
@MainActor
final class VNCWebController: NSObject {
    enum Event {
        case connected
        case title(String)
        case ended((any Error)?)
    }

    static let scheme = "PatchNode-vnc"

    let webView: WKWebView
    private let onEvent: (Event) -> Void
    private var connection: ProxmoxVNCConnection?
    private var pump: Task<Void, Never>?
    /// Keys and pointer events, in order, through one writer task.
    private var outgoing: AsyncStream<Data>.Continuation?
    private var writer: Task<Void, Never>?
    private var opener: Task<Void, Never>?
    private var pageReady = false
    private var scale: Bool

    init(scale: Bool, onEvent: @escaping (Event) -> Void) {
        self.scale = scale
        self.onEvent = onEvent
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.limitsNavigationsToAppBoundDomains = false
        configuration.preferences.isTextInteractionEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let schemeHandler = LocalNoVNCSchemeHandler()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: Self.scheme)
        let relay = MessageRelay()
        configuration.userContentController.add(relay, contentWorld: .page, name: "vnc")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = false
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black
        super.init()
        relay.target = self
        webView.navigationDelegate = self
    }

    func start(_ link: @escaping @Sendable () async throws -> ProxmoxVNCConnection) {
        opener = Task { [weak self] in
            do {
                let connection = try await link()
                guard let self, !Task.isCancelled else {
                    connection.close()
                    return
                }
                self.connection = connection
                let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
                self.outgoing = continuation
                self.writer = Task {
                    for await data in stream { await connection.send(data) }
                }
                self.webView.load(URLRequest(url: URL(string: "\(Self.scheme)://console/index.html")!))
            } catch {
                self?.onEvent(.ended(error))
            }
        }
    }

    func stop() {
        opener?.cancel()
        pump?.cancel()
        outgoing?.finish()
        writer?.cancel()
        connection?.close()
        connection = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
    }

    func setScale(_ scale: Bool) {
        self.scale = scale
        call("PatchNode.setScale(s)", ["s": scale])
    }

    func showKeyboard() { call("PatchNode.showKeyboard()") }
    func sendCtrlAltDel() { call("PatchNode.ctrlAltDel()") }
    func sendKey(_ name: String) { call("PatchNode.key(k)", ["k": name]) }

    private func call(_ script: String, _ arguments: [String: Any] = [:]) {
        guard pageReady else { return }
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { _ in }
    }

    fileprivate func received(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "ready":
            pageReady = true
            startRFB()
        case "send":
            guard let text = message["data"] as? String, let data = Data(base64Encoded: text) else { return }
            outgoing?.yield(data)
        case "connected":
            onEvent(.connected)
        case "title":
            onEvent(.title(message["title"] as? String ?? ""))
        case "securityfailure":
            onEvent(.ended(VNCAuthenticationFailure()))
        case "disconnected", "close":
            onEvent(.ended(nil))
        default:
            break
        }
    }

    /// The password goes as an argument of the call, never in the page source
    /// or a URL. The stream is then relayed in order, one frame at a time.
    private func startRFB() {
        guard let connection, pump == nil else { return }
        webView.callAsyncJavaScript(
            "PatchNode.start(p, s)", arguments: ["p": connection.password, "s": scale], in: nil, in: .page
        ) { _ in }
        pump = Task { [weak self, webView] in
            do {
                for try await data in connection.output {
                    _ = try? await webView.callAsyncJavaScript(
                        "PatchNode.receive(d)", arguments: ["d": data.base64EncodedString()], in: nil, contentWorld: .page
                    )
                }
                if Task.isCancelled { return }
                _ = try? await webView.callAsyncJavaScript("PatchNode.remoteClosed()", arguments: [:], in: nil, contentWorld: .page)
                self?.onEvent(.ended(nil))
            } catch is CancellationError {
            } catch {
                self?.onEvent(.ended(error))
            }
        }
    }
}

extension VNCWebController: WKNavigationDelegate {
    /// Only the local page; anything else (a link, a redirect) is refused.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.scheme == Self.scheme ? .allow : .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onEvent(.ended(VNCPageFailure()))
    }
}

/// Breaks the retain cycle between the content controller and the controller.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var target: VNCWebController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only the local page may talk to the app.
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == VNCWebController.scheme,
              let body = message.body as? [String: Any]
        else { return }
        target?.received(body)
    }
}

/// Serves the embedded noVNC files; nothing outside its folder.
private final class LocalNoVNCSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host() == "console",
              let directory = NoVNCResources.directory,
              let file = NoVNCResources.file(forPath: url.path(percentEncoded: false), in: directory),
              let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": NoVNCResources.mimeType(for: file),
            "Content-Length": String(data.count),
            "Cache-Control": "no-store",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// Hosts the controller's web view.
struct VNCWebSurface: UIViewRepresentable {
    let controller: VNCWebController

    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
