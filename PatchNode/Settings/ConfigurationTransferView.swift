import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import PatchNodeCore
import ProxmoxKit

/// Settings › Export and import: the configuration as a file or a QR code,
/// **without tokens**, and importing one back (preview, then merge or replace).
struct ConfigurationTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLockController.self) private var lockController
    @Environment(AppModel.self) private var model
    @Query(sort: \ServiceConfig.name) private var configs: [ServiceConfig]
    @Query private var favorites: [PromQLFavorite]
    @Query(sort: \HomeAssistantPin.sortOrder) private var pins: [HomeAssistantPin]
    @AppStorage(TabSelection.storageKey) private var storedTabs = ""
    @AppStorage(DashboardCard.orderKey) private var storedOrder = ""
    @AppStorage(DemoMode.key) private var demoMode = false

    @State private var exportURL: URL?
    @State private var qrImage: UIImage?
    @State private var showsQRCode = false
    @State private var showsFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pending: ConfigurationExport?
    @State private var message: String?

    private let secretStore: any SecretStore

    init(secretStore: any SecretStore = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    var body: some View {
        if demoMode {
            ContentUnavailableView(
                "Not available in the demo",
                systemImage: "sparkles.rectangle.stack",
                description: Text("Exit the demo to export or import your own services.")
            )
            .navigationTitle("Export and import")
        } else {
            transferList
        }
    }

    private var transferList: some View {
        List {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL, preview: SharePreview(exportURL.lastPathComponent)) {
                        Label("Share the configuration file", systemImage: "square.and.arrow.up")
                    }
                }
                if qrImage != nil {
                    Button("Show as a QR code", systemImage: "qrcode") { showsQRCode = true }
                } else if exportURL != nil {
                    Text("Too many services for a QR code: share the file instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("\(configs.uniqued(by: \.id).count) services, their names and addresses, PromQL charts, Home Assistant entities, tabs and dashboard order. **No token or password**: enter them again on the other iPhone. Keep the file for yourself: it describes your network.")
            }

            Section {
                Button("Import a file", systemImage: "doc") { showsFileImporter = true }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Import a QR code from a photo or screenshot", systemImage: "qrcode.viewfinder")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("You see what would change before anything is written.")
            }

            if let message {
                Section {
                    Text(message)
                }
            }
        }
        .readableWidth()
        .navigationTitle("Export and import")
        .task(id: exportSignature) { prepareExport() }
        .onDisappear { removeExportFile() }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.json, .data]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            // Read at most a little more than the limit: a huge file is refused.
            let data = (try? FileHandle(forReadingFrom: url))
                .flatMap { handle in defer { try? handle.close() }; return try? handle.read(upToCount: ConfigurationExport.maxFileSize + 1) }
            read(data)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                guard let text = data.flatMap(Self.qrMessage(in:)) else {
                    message = String(localized: "No PatchNode QR code found in this image.")
                    return
                }
                read(Data(text.utf8))
            }
        }
        .sheet(isPresented: $showsQRCode) {
            if let qrImage { QRCodeSheet(image: qrImage) }
        }
        .sheet(item: Binding(get: { pending.map(PendingImport.init) }, set: { if $0 == nil { pending = nil } })) { item in
            ImportPreviewView(file: item.file, existing: currentExport(), apply: apply)
        }
    }

    // MARK: - Export

    /// Changes whenever something exported changes.
    private var exportSignature: String {
        "\(configs.map { "\($0.id)\($0.name)\($0.urlString)" })|\(favorites.count)|\(pins.count)|\(storedTabs)|\(storedOrder)"
    }

    private func currentExport() -> ConfigurationExport {
        ConfigurationExport(
            services: configs.uniqued(by: \.id).map { .init(id: $0.id, kind: $0.kindRawValue, name: $0.name, url: $0.urlString) },
            favorites: favorites.uniqued(by: \.id).map {
                .init(id: $0.id, name: $0.name, query: $0.query, unit: $0.unitRawValue, rangeMinutes: $0.rangeMinutes, serviceID: $0.serviceID, createdAt: $0.createdAt)
            },
            pins: pins.uniqued(by: \.pinKey).map { .init(id: $0.id, serviceID: $0.serviceID, entityID: $0.entityID, sortOrder: $0.sortOrder) },
            tabs: storedTabs.isEmpty ? nil : storedTabs,
            dashboardOrder: storedOrder.isEmpty ? nil : storedOrder
        )
    }

    private func prepareExport() {
        removeExportFile()
        // Leftovers of an earlier session (app killed while this screen was open).
        let tmp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path())) ?? [] where name.hasSuffix(".PatchNode.json") {
            try? FileManager.default.removeItem(at: tmp.appending(path: name))
        }
        guard !configs.isEmpty, let data = try? currentExport().encoded() else {
            qrImage = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appending(path: ConfigurationExport.fileName())
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch {
            exportURL = nil
        }
        qrImage = ConfigurationQRCode.fits(data) ? Self.qrCode(for: data) : nil
    }

    private func removeExportFile() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
    }

    private static func qrCode(for data: Data) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func qrMessage(in imageData: Data) -> String? {
        guard let image = CIImage(data: imageData),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }

    // MARK: - Import

    private func read(_ data: Data?) {
        guard let data else {
            message = String(localized: "The file couldn't be read.")
            return
        }
        do {
            pending = try ConfigurationExport.decode(data)
            message = nil
        } catch {
            message = switch error {
            case .tooLarge: String(localized: "This file is too large to be a PatchNode configuration.")
            case .notPatchNode, .unreadable: String(localized: "This isn't a PatchNode configuration file.")
            case .newerVersion: String(localized: "This file comes from a newer PatchNode: update the app first.")
            }
        }
    }

    /// Replacing removes services and their tokens: Face ID first, like any action.
    private func apply(_ plan: ConfigurationImportPlan) async -> Bool {
        if plan.mode == .replace, !plan.servicesToRemove.isEmpty {
            guard await lockController.authenticateForAction(reason: String(localized: "Replace the configuration")) else { return false }
        }
        // Removed services lose their token (synced copy included only if this
        // device syncs tokens). Imported ones lose this device's leftover copy
        // only: a copy synced by another device stays there, and the binding of
        // every token to its server (`CredentialOrigin`) keeps the file's address
        // from ever receiving a token saved for another server.
        // An ID removed and imported again (same file) keeps any synced copy:
        // its binding already protects it.
        let removedIDs = Set(plan.servicesToRemove).subtracting(plan.servicesToAdd.map(\.id))
        for id in plan.servicesToRemove + plan.servicesToAdd.map(\.id) {
            do {
                if removedIDs.contains(id) {
                    try await secretStore.delete(for: id)
                } else {
                    try await secretStore.deleteDeviceOnly(for: id)
                }
            } catch {
                message = String(localized: "A token couldn't be removed from the Keychain: the configuration wasn't changed, but some tokens may already be gone.")
                return false
            }
        }
        let removed = Set(plan.servicesToRemove)
        for config in configs where removed.contains(config.id) {
            if let url = config.url { CertificateRegistry.shared.remove(for: url) }
            SMARTSettingsStore.remove(config.id)
            modelContext.delete(config)
        }
        model.reloadSMARTSettings()
        for favorite in favorites where removed.contains(favorite.serviceID) { modelContext.delete(favorite) }
        for pin in pins where removed.contains(pin.serviceID) { modelContext.delete(pin) }
        for service in plan.servicesToAdd {
            guard let kind = ServiceKind(rawValue: service.kind) else { continue }
            modelContext.insert(ServiceConfig(id: service.id, kind: kind, name: service.name, urlString: service.url))
        }
        for favorite in plan.favoritesToAdd {
            modelContext.insert(PromQLFavorite(
                id: favorite.id, name: favorite.name, query: favorite.query, unit: PromQLUnit(rawValue: favorite.unit) ?? .none,
                rangeMinutes: favorite.rangeMinutes, serviceID: favorite.serviceID, createdAt: favorite.createdAt
            ))
        }
        for pin in plan.pinsToAdd {
            modelContext.insert(HomeAssistantPin(id: pin.id, serviceID: pin.serviceID, entityID: pin.entityID, sortOrder: pin.sortOrder))
        }
        do {
            try modelContext.save()
        } catch {
            // Nothing half-applied may be saved later by an autosave.
            modelContext.rollback()
            message = String(localized: "The configuration couldn't be saved.")
            return false
        }
        // Stores forget any token they held for these IDs.
        for id in plan.servicesToRemove + plan.servicesToAdd.map(\.id) { model.credentialChanged(for: id) }
        if let tabs = plan.tabs { storedTabs = tabs }
        if let order = plan.dashboardOrder { storedOrder = order }
        message = String(localized: "\(plan.servicesToAdd.count) services imported. Enter their tokens: Settings › the service › Edit.")
        return true
    }
}

private struct PendingImport: Identifiable {
    let file: ConfigurationExport
    var id: Date { file.exportedAt }
}

/// What the import would change; merge or replace, then confirm.
private struct ImportPreviewView: View {
    let file: ConfigurationExport
    let existing: ConfigurationExport
    let apply: (ConfigurationImportPlan) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ConfigurationImportPlan.Mode = .merge
    @State private var confirmsReplace = false
    @State private var isApplying = false

    private var plan: ConfigurationImportPlan {
        ConfigurationImportPlan(file: file, existing: existing, mode: mode, fixedURL: { $0.fixedURL })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Merge").tag(ConfigurationImportPlan.Mode.merge)
                        Text("Replace").tag(ConfigurationImportPlan.Mode.replace)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .merge
                         ? "Keeps your current services and adds the new ones."
                         : "Removes your current services and their tokens, then adds the file's services.")
                }
                let plan = plan
                Section("What changes") {
                    if !plan.servicesToRemove.isEmpty {
                        Label("\(plan.servicesToRemove.count) services removed, with their tokens", systemImage: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    ForEach(plan.servicesToAdd, id: \.id) { service in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: service.name)
                                // The address matters more than the name: a file can
                                // give a familiar name to someone else's server.
                                Text(verbatim: Self.origin(of: service.url))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "plus.circle").foregroundStyle(.green)
                        }
                    }
                    if plan.favoritesToAdd.count > 0 {
                        Text("\(plan.favoritesToAdd.count) PromQL charts")
                    }
                    if plan.pinsToAdd.count > 0 {
                        Text("\(plan.pinsToAdd.count) Home Assistant entities")
                    }
                    if plan.isEmpty {
                        Text("Nothing new to import.").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("Import only files you made yourself. Check each address: your tokens will be sent there once you enter them.", systemImage: "exclamationmark.shield")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if !plan.skipped.isEmpty {
                    Section("Skipped") {
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, entry in
                            LabeledContent {
                                Text(reasonText(entry.reason))
                            } label: {
                                Text(verbatim: entry.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .merge ? "Import" : "Replace") {
                        if mode == .replace, !plan.servicesToRemove.isEmpty {
                            confirmsReplace = true
                        } else {
                            run(plan)
                        }
                    }
                    .disabled(plan.isEmpty || isApplying)
                }
            }
            .confirmationDialog(
                Text("Remove \(plan.servicesToRemove.count) services and their tokens?"),
                isPresented: $confirmsReplace, titleVisibility: .visible
            ) {
                Button("Replace the configuration", role: .destructive) { run(plan) }
            } message: {
                Text(verbatim: existing.services.filter { plan.servicesToRemove.contains($0.id) }.map(\.name).joined(separator: ", "))
            }
        }
    }

    private func run(_ plan: ConfigurationImportPlan) {
        isApplying = true
        Task {
            if await apply(plan) { dismiss() }
            isApplying = false
        }
    }

    private func reasonText(_ reason: ConfigurationImportPlan.SkipReason) -> String {
        switch reason {
        case .duplicate: String(localized: "Already configured")
        case .invalidURL: String(localized: "Invalid address")
        case .unknownKind: String(localized: "Unknown service type")
        case .emptyName: String(localized: "No name")
        case .tooMany: String(localized: "Too many services")
        case .reserved: String(localized: "Reserved for the demo")
        }
    }

    /// Host and port only.
    private static func origin(of url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host else { return url }
        return components.port.map { "\(host):\($0)" } ?? host
    }
}

private struct QRCodeSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Always dark modules on white, in dark mode too: a quiet zone
                // that scanners read, also on a screenshot.
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .background(.white, in: .rect(cornerRadius: 12))
                    .frame(maxWidth: 420)
                    .accessibilityLabel(Text("QR code of the configuration"))
                Text("On the other iPhone, take a photo or a screenshot of this code, then Settings › Export and import › Import a QR code. No token is included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
