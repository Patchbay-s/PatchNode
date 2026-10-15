import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PatchNodeCore

private struct EchoResponder: DemoResponder {
    func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        .json(object: ["method": request.method, "path": request.path, "q": request.query["limit"] ?? ""])
    }
}

struct DemoTransportTests {
    @Test func demoHostsAreAnsweredOnTheDevice() async throws {
        let host = "echo-\(UUID().uuidString.lowercased()).\(DemoServer.domain)"
        DemoServer.register(EchoResponder(), host: host)
        let client = HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), label: nil, log: nil)
        let data = try await client.fetchOK(HTTPRequestSpec(method: .get, url: URL(string: "https://\(host)/api/items?limit=5")!))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["method": "GET", "path": "/api/items", "q": "5"])
    }

    @Test func unknownDemoHostGets404WithoutNetwork() async throws {
        let client = HTTPClient(sessions: RenewableSession(make: HTTPClient.makeSession), maxAttempts: 1, label: nil, log: nil)
        let (_, response) = try await client.send(HTTPRequestSpec(method: .get, url: URL(string: "https://nobody.\(DemoServer.domain)/x")!))
        #expect(response.statusCode == 404)
    }

    @Test func onlyTheReservedDomainIsDemo() {
        #expect(DemoServer.isDemo(URL(string: "https://proxmox.patchnode-demo.invalid:8006")!))
        #expect(!DemoServer.isDemo(URL(string: "https://patchnode-demo.invalid.example.com")!))
        #expect(!DemoServer.isDemo(URL(string: "https://proxmox.example.invalid")!))
    }

    @Test func realHostsAreNeverIntercepted() {
        let real = [
            "https://proxmox.example.invalid:8006/api2/json/version",
            "https://api.tailscale.com/api/v2/tailnet/-/devices",
            "https://patchnode-demo.invalid.example.com/x",
            "https://user:pw@proxmox.example.invalid/x",
        ]
        for text in real {
            #expect(!DemoURLProtocol.canInit(with: URLRequest(url: URL(string: text)!)), "\(text)")
        }
        #expect(DemoURLProtocol.canInit(with: URLRequest(url: URL(string: "https://proxmox.patchnode-demo.invalid:8006/api2/json/version")!)))
        #expect(DemoURLProtocol.canInit(with: URLRequest(url: URL(string: "https://PROXMOX.PatchNode-Demo.invalid/x")!)))
    }

    @Test func catalogHasOneServiceOfEveryTypeOnDemoHosts() {
        #expect(Set(DemoCatalog.services.map(\.kind)) == Set(ServiceKind.allCases))
        #expect(DemoCatalog.serviceIDs.count == ServiceKind.allCases.count)
        #expect(DemoCatalog.services.allSatisfy { DemoServer.isDemo($0.url) && $0.url.scheme == "https" })
    }
}
