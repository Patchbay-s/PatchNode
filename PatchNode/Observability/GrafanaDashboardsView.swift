import SwiftUI
import WebKit
import PatchNodeCore
import ObservabilityKit

struct GrafanaDashboardsView: View {
    @Environment(ObservabilityStore.self) private var store
    @State private var searchText = ""

    var body: some View {
        List(filtered) { item in
            if let url = item.url {
                NavigationLink {
                    Group {
                        if DemoServer.isDemo(url) {
                            // A web page: nothing to show without a real Grafana.
                            ContentUnavailableView(
                                "Not available in the demo",
                                systemImage: "sparkles.rectangle.stack",
                                description: Text("With your own Grafana, the dashboard opens here and you sign in as usual.")
                            )
                        } else {
                            GrafanaWebView(url: url)
                                .ignoresSafeArea(edges: .bottom)
                        }
                    }
                    .navigationTitle(Text(verbatim: item.dashboard.title))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    DashboardRow(item: item)
                }
            } else {
                DashboardRow(item: item)
                    .foregroundStyle(.secondary)
            }
        }
        .readableWidth(ReadableWidth.data)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView("No dashboards.", systemImage: "square.grid.3x3")
            }
        }
        .navigationTitle("Grafana dashboards")
        .searchable(text: $searchText, prompt: Text("Search dashboards"))
    }

    private var filtered: [ObservabilityInventory.DashboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.inventory.dashboards }
        return store.inventory.dashboards.filter {
            $0.dashboard.title.localizedStandardContains(query) || ($0.dashboard.folder?.localizedStandardContains(query) ?? false)
        }
    }
}

private struct DashboardRow: View {
    let item: ObservabilityInventory.DashboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.dashboard.title)
            if let folder = item.dashboard.folder, !folder.isEmpty {
                Text(verbatim: folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Grafana in an embedded browser. The user signs in inside the page; the API
/// token is never injected into the URL or cookies. Only HTTPS pages of the
/// Grafana host are loaded in the main frame, certificate checks are left to the
/// system, and the session lives in memory (a non-persistent data store).
struct GrafanaWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(allowedHost: url.host, allowedPort: url.port ?? 443)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = GrafanaWebSession.dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if url.scheme == "https" {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let allowedHost: String?
        private let allowedPort: Int

        init(allowedHost: String?, allowedPort: Int) {
            self.allowedHost = allowedHost?.lowercased()
            self.allowedPort = allowedPort
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            let scheme = url.scheme?.lowercased()
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame {
                let sameOrigin = url.host?.lowercased() == allowedHost && (url.port ?? 443) == allowedPort
                return scheme == "https" && sameOrigin ? .allow : .cancel
            }
            // Panels may embed about:blank, blob: or data: frames.
            return ["https", "about", "blob", "data"].contains(scheme ?? "") ? .allow : .cancel
        }
    }
}

/// One in-memory web session for the app's lifetime: signing in to Grafana once
/// covers every dashboard, and nothing is written to disk.
enum GrafanaWebSession {
    @MainActor static let dataStore = WKWebsiteDataStore.nonPersistent()

    /// Called when the app goes to the background (and locks): the Grafana
    /// session is signed out, like the in-memory API tokens.
    @MainActor static func clear() {
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
}
