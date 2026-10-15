import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PatchNodeCore

// BUGS.md ÉLEVÉ: an NPM "LAN only" Access List answers 403 with an HTML page when
// the VPN is off. That is the proxy, not a refused token.

private func response(_ status: Int, contentType: String?) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://proxmox.example.invalid")!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: contentType.map { ["Content-Type": $0] } ?? [:]
    )!
}

private let npmPage = Data("""
<html>
<head><title>403 Forbidden</title></head>
<body><center><h1>403 Forbidden</h1></center><hr><center>openresty</center></body>
</html>
""".utf8)

@Suite("Reverse proxy 403 detection")
struct ProxyBlockDetectionTests {
    @Test func htmlContentTypeIsTheProxy() {
        #expect(HTTPClient.isProxyBlockPage(response(403, contentType: "text/html"), body: npmPage))
        #expect(HTTPClient.isProxyBlockPage(response(403, contentType: "text/html; charset=utf-8"), body: Data()))
    }

    @Test func htmlBodyWithoutContentTypeIsTheProxy() {
        #expect(HTTPClient.isProxyBlockPage(response(403, contentType: nil), body: npmPage))
        #expect(HTTPClient.isProxyBlockPage(response(403, contentType: nil), body: Data("  \n<!DOCTYPE html><html></html>".utf8)))
    }

    @Test func serviceAnswersAreNotTheProxy() {
        // Proxmox, Portainer, Grafana: JSON; Home Assistant, AdGuard: plain text.
        #expect(!HTTPClient.isProxyBlockPage(response(403, contentType: "application/json;charset=UTF-8"), body: Data(#"{"data":null}"#.utf8)))
        #expect(!HTTPClient.isProxyBlockPage(response(403, contentType: "text/plain"), body: Data("403: Forbidden".utf8)))
        #expect(!HTTPClient.isProxyBlockPage(response(403, contentType: nil), body: Data()))
    }

    /// docker-socket-proxy (HAProxy) refusing a disabled endpoint: the service's own
    /// refusal, even though it is an HTML page.
    @Test func haproxySocketProxyRefusalIsTheService() {
        let page = Data("<html><body><h1>403 Forbidden</h1>\nRequest forbidden by administrative rules.\n</body></html>\n".utf8)
        #expect(!HTTPClient.isProxyBlockPage(response(403, contentType: "text/html"), body: page))
    }

    @Test func blockedByProxyMapsToItsOwnProviderError() async {
        struct Fake: HTTPClientProtocol {
            func send(_ request: HTTPRequestSpec) async throws -> (Data, HTTPURLResponse) {
                throw HTTPClientError.blockedByProxy
            }
        }
        await #expect(throws: ServiceProviderError.blockedByProxy) {
            _ = try await Fake().fetchOK(HTTPRequestSpec(method: .get, url: URL(string: "https://proxmox.example.invalid")!))
        }
    }
}
