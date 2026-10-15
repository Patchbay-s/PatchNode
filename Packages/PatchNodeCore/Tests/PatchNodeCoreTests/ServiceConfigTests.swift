#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
@testable import PatchNodeCore

@MainActor
struct ServiceConfigTests {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ServiceConfig.self, configurations: configuration)
        return ModelContext(container)
    }

    @Test func insertThenFetchPreservesFields() throws {
        let context = try makeContext()
        let id = UUID()
        context.insert(ServiceConfig(id: id, kind: .grafana, name: "Grafana", urlString: "https://grafana.example.invalid"))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ServiceConfig>())
        #expect(fetched.count == 1)
        let config = try #require(fetched.first)
        #expect(config.id == id)
        #expect(config.name == "Grafana")
        #expect(config.urlString == "https://grafana.example.invalid")
        #expect(config.kind == .grafana)
        #expect(config.kindRawValue == ServiceKind.grafana.rawValue)
    }

    @Test func settingKindUpdatesRawValue() {
        let config = ServiceConfig(kind: .proxmoxVE, name: "PVE", urlString: "https://proxmox.example.invalid:8006")
        config.kind = .uptimeKuma
        #expect(config.kindRawValue == ServiceKind.uptimeKuma.rawValue)
        #expect(config.kind == .uptimeKuma)
    }

    @Test func urlIsValidForWellFormedString() throws {
        let config = ServiceConfig(kind: .proxmoxVE, name: "PVE", urlString: "https://proxmox.example.invalid:8006")
        let url = try #require(config.url)
        #expect(url.scheme == "https")
        #expect(url.host == "proxmox.example.invalid")
        #expect(url.port == 8006)
    }

    @Test func modelExposesNoSecretField() {
        let config = ServiceConfig(kind: .homeAssistant, name: "HA", urlString: "https://ha.example.invalid")
        let labels = Mirror(reflecting: config).children.compactMap { $0.label?.lowercased() }
        for forbidden in ["token", "secret", "password"] {
            #expect(!labels.contains { $0.contains(forbidden) }, "ServiceConfig must not store a \(forbidden)")
        }
    }
}
#endif
