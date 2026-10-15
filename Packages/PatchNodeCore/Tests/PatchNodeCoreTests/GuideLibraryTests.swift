import Foundation
import Testing
@testable import PatchNodeCore

struct GuideLibraryTests {
    @Test func everyServiceTypeAndTheNetworkHaveAGuide() {
        #expect(GuideLibrary.all.count == ServiceKind.allCases.count + 2)
        #expect(GuideLibrary.guide(for: .ssh).topic == .ssh)
        for kind in ServiceKind.allCases {
            #expect(GuideLibrary.guide(for: .service(kind)).topic == .service(kind))
        }
    }

    @Test func serviceGuidesFollowTheOutline() {
        for kind in ServiceKind.allCases {
            let guide = GuideLibrary.guide(for: .service(kind))
            #expect(guide.sections.map(\.kind) == GuideSectionKind.allCases, "\(kind)")
            for section in guide.sections {
                #expect(!section.blocks.isEmpty, "\(kind) \(section.kind)")
            }
        }
    }

    @Test func everyErrorTypeHasATroubleshootingEntryInEveryGuide() {
        for guide in GuideLibrary.all {
            let problems = guide.troubleshooting.compactMap(\.problem)
            #expect(problems.starts(with: GuideProblem.allCases), "\(guide.topic)")
            for problem in GuideProblem.allCases {
                let entry = guide.troubleshooting(for: problem)
                #expect(entry.problem == problem)
                #expect(!entry.blocks.isEmpty)
            }
        }
    }

    @Test func everyTextExistsInEnglishAndFrench() {
        for text in allTexts() {
            #expect(!text.en.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!text.fr.trimmingCharacters(in: .whitespaces).isEmpty, "\(text.en)")
        }
        #expect(GuideText("Hello", "Bonjour").resolved(languageCode: "fr") == "Bonjour")
        #expect(GuideText("Hello", "Bonjour").resolved(languageCode: "pt") == "Hello")
        #expect(GuideText("Hello", "Bonjour").resolved(languageCode: "de") == "Hello")
    }

    @Test func everyTextIsTranslatedToSpanishGermanAndItalian() {
        let texts = allTexts()
        for (code, table) in [("es", GuideText.es), ("de", GuideText.de), ("it", GuideText.it)] {
            for text in texts {
                let translated = text.resolved(languageCode: code)
                #expect(table[text.en] != nil, "\(code): \(text.en)")
                #expect(!translated.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            // No stale entry left behind by an edited English text.
            let used = Set(texts.map(\.en))
            #expect(Set(table.keys).subtracting(used).isEmpty, "\(code): \(Set(table.keys).subtracting(used))")
        }
    }

    @Test func requiredPitfallsAreCovered() {
        let pve = corpus(.service(.proxmoxVE))
        for needle in ["Scheme", "https", "301", "Privilege Separation", "PatchNodePower", "VM.PowerMgmt", "'monitor@pve!patchnode'", "one service per node",
                       "'PVEAuditor,PatchNodeConsole'", "'PVEAuditor,PatchNodePower'", "'PVEAuditor,PatchNodeNodeConsole'",
                       "pveum user token permissions monitor@pve patchnode --path"] {
            #expect(pve.contains(needle), "Proxmox guide lacks \(needle)")
        }
        let tailscale = corpus(.service(.tailscale))
        for needle in ["Trust credentials", "OAuth clients", "Devices › Core", "Settings › Keys"] {
            #expect(tailscale.contains(needle), "Tailscale guide lacks \(needle)")
        }
        let docker = corpus(.service(.dockerSocketProxy))
        for needle in ["docker-socket-proxy", "0.0.0.0", "Satisfy All", "POST: 0", "POST=1", "docker.sock", "CONTAINERS=1"] {
            #expect(docker.contains(needle), "Docker guide lacks \(needle)")
        }
        let crowdSec = corpus(.service(.crowdSec))
        for needle in ["cscli bouncers add", "127.0.0.1", "null"] {
            #expect(crowdSec.contains(needle), "CrowdSec guide lacks \(needle)")
        }
        #expect(corpus(.service(.uptimeKuma)).contains("slug"))
        #expect(corpus(.service(.grafana)).contains("Viewer"))
        let network = corpus(.networkPrerequisites)
        for needle in ["Tailscale", "Split DNS", "certificate", "Access List", "CrowdSec", "401/403"] {
            #expect(network.contains(needle), "Network guide lacks \(needle)")
        }
    }

    /// Commands and examples use documentation names and addresses only.
    @Test func onlyGenericHostsAndNoSecrets() throws {
        let hostPattern = try Regex(#"(?:[a-z0-9-]+\.)+(?:com|net|org|io|fr|lan|local|home|arpa|dev)\b"#)
        let ipPattern = try Regex(#"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#)
        let allowedHosts: Set<String> = ["api.tailscale.com", "tailscale.com"]
        let allowedIPs = ["192.0.2.", "100.64.0.0", "127.0.0.1", "0.0.0.0"]
        let secretPattern = try Regex(#"[A-Za-z0-9_\-]{28,}"#)
        for guide in GuideLibrary.all {
            let text = corpus(guide.topic)
            for match in text.matches(of: hostPattern) {
                let host = String(text[match.range]).lowercased()
                #expect(host == "example.com" || host.hasSuffix(".example.com") || allowedHosts.contains(host)
                        || host.hasSuffix(".ts.net") && host.contains("tailnet"), "\(guide.topic): \(host)")
            }
            for match in text.matches(of: ipPattern) {
                let ip = String(text[match.range])
                #expect(allowedIPs.contains { ip.hasPrefix($0) }, "\(guide.topic): \(ip)")
            }
            for match in text.matches(of: secretPattern) {
                let value = String(text[match.range])
                // Placeholders only: zeros or x's.
                #expect(value.filter { !"0-x".contains($0) }.count < 12 || value.contains("CNTRL") && value.contains("xxxx")
                        || value.contains("-") && value.split(separator: "-").allSatisfy { $0.count < 28 },
                        "\(guide.topic): \(value)")
            }
        }
    }

    // MARK: Helpers

    private func texts(_ blocks: [GuideBlock]) -> [GuideText] {
        blocks.flatMap { block -> [GuideText] in
            switch block {
            case .paragraph(let text), .warning(let text): [text]
            case .steps(let list), .bullets(let list): list
            case .code: []
            }
        }
    }

    private func allTexts() -> [GuideText] {
        GuideLibrary.all.flatMap { guide in
            [guide.title, guide.summary]
                + guide.sections.flatMap { texts($0.blocks) }
                + guide.troubleshooting.flatMap { [$0.title] + texts($0.blocks) }
        }
    }

    private func all(_ text: GuideText) -> String {
        ([text.en, text.fr] + ["es", "de", "it"].map { text.resolved(languageCode: $0) }).joined(separator: "\n")
    }

    private func corpus(_ topic: GuideTopic) -> String {
        let guide = GuideLibrary.guide(for: topic)
        let blocks = guide.sections.flatMap(\.blocks) + guide.troubleshooting.flatMap(\.blocks)
        return blocks.map { block -> String in
            switch block {
            case .code(let code): code
            case .paragraph(let text), .warning(let text): all(text)
            case .steps(let list), .bullets(let list): list.map(all).joined(separator: "\n")
            }
        }.joined(separator: "\n") + guide.troubleshooting.map { $0.title.en }.joined(separator: "\n")
    }
}
