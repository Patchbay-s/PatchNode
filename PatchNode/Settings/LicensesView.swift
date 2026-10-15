import SwiftUI
import RemoteAccessKit

/// Settings › About › Licenses: the third-party code PatchNode 1.2 ships
/// (terminal, SSH, graphical console), with versions pinned in the project
/// and their license texts.
struct LicensesView: View {
    struct Component: Identifiable {
        let name: String
        let version: String
        let license: String
        let purpose: LocalizedStringKey
        /// Text files: in the app bundle, or in noVNC's folder.
        let files: [String]
        var inNoVNC = false

        var id: String { name }
    }

    static let components: [Component] = [
        Component(name: "SwiftTerm", version: "1.10.1", license: "MIT", purpose: "Terminal", files: ["SwiftTerm-LICENSE"]),
        Component(name: "SwiftNIO SSH", version: "0.15.0", license: "Apache-2.0", purpose: "SSH", files: ["swift-nio-ssh-LICENSE"]),
        Component(name: "SwiftNIO", version: "2.103.0", license: "Apache-2.0", purpose: "SSH", files: ["swift-nio-LICENSE", "swift-nio-NOTICE"]),
        Component(name: "Swift Crypto", version: "4.5.2", license: "Apache-2.0", purpose: "SSH", files: ["swift-crypto-LICENSE", "swift-crypto-NOTICE"]),
        Component(name: "Swift ASN.1", version: "1.7.3", license: "Apache-2.0", purpose: "SSH", files: ["swift-asn1-LICENSE", "swift-asn1-NOTICE"]),
        Component(name: "Swift Atomics", version: "1.3.1", license: "Apache-2.0", purpose: "SSH", files: ["swift-atomics-LICENSE"]),
        Component(name: "Swift Collections", version: "1.7.0", license: "Apache-2.0", purpose: "SSH", files: ["swift-collections-LICENSE"]),
        Component(name: "Swift System", version: "1.8.1", license: "Apache-2.0", purpose: "SSH", files: ["swift-system-LICENSE"]),
        Component(name: "noVNC", version: "1.7.0", license: "MPL-2.0", purpose: "Graphical console", files: ["noVNC-LICENSE.txt", "LICENSE.MPL-2.0", "LICENSE.BSD-3-Clause"], inNoVNC: true),
        Component(name: "pako (in noVNC)", version: "1.7.0", license: "MIT", purpose: "Graphical console", files: ["pako-LICENSE"], inNoVNC: true),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.components) { component in
                    NavigationLink {
                        LicenseTextView(component: component)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(component.name) \(component.version)")
                            HStack(spacing: 0) {
                                Text(component.purpose)
                                Text(verbatim: " · \(component.license)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Embedded unmodified, versions pinned. noVNC runs inside the app, offline: it is never loaded from the internet.")
            }
        }
        .readableWidth()
        .navigationTitle("Licenses")
    }
}

private struct LicenseTextView: View {
    let component: LicensesView.Component

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: ReadableWidth.form, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(verbatim: component.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        component.files.compactMap { name -> String? in
            let url: URL? = component.inNoVNC
                ? NoVNCResources.directory?.appending(path: "licenses/\(name)")
                : Bundle.main.url(forResource: name, withExtension: "txt")
            return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n────────\n\n")
    }
}
