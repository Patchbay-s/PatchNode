import Foundation

/// Text of a built-in guide. Guides are documents shipped with the app (read
/// offline, checked by tests): English and French sit side by side here,
/// Spanish, German and Italian in tables keyed by the English text
/// (GuideText+es/de/it); the screens' own labels stay in the String Catalog.
public struct GuideText: Sendable, Hashable {
    public let en: String
    public let fr: String

    public init(_ en: String, _ fr: String) {
        self.en = en
        self.fr = fr
    }

    /// The text in that language, English when the language isn't covered.
    public func resolved(languageCode: String?) -> String {
        switch languageCode {
        case "fr": fr
        case "es": Self.es[en] ?? en
        case "de": Self.de[en] ?? en
        case "it": Self.it[en] ?? en
        default: en
        }
    }

    /// The app's language, resolved once: it changes only with a relaunch.
    private static let appLanguageCode = Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) }

    /// In the language the app is running in.
    public var localized: String {
        resolved(languageCode: Self.appLanguageCode)
    }
}

/// One piece of a guide's section.
public enum GuideBlock: Sendable, Hashable {
    case paragraph(GuideText)
    /// Numbered steps.
    case steps([GuideText])
    case bullets([GuideText])
    /// A command or configuration snippet, copied in one tap. Never localized,
    /// generic hosts only (example.com, 192.0.2.x), never a secret.
    case code(String)
    /// A pitfall or security warning, shown highlighted.
    case warning(GuideText)
}

/// The fixed outline of every service guide.
public enum GuideSectionKind: String, Sendable, Hashable, CaseIterable {
    /// What the service brings to PatchNode.
    case purpose
    /// Creating the account or token, step by step.
    case setup
    /// Least privilege: read-only first, then the rights for actions.
    case rights
    /// Reverse proxy configuration.
    case reverseProxy
    /// Checking from a computer with curl.
    case verify
}

public struct GuideSection: Sendable, Hashable, Identifiable {
    public let kind: GuideSectionKind
    public let blocks: [GuideBlock]
    public var id: GuideSectionKind { kind }

    public init(_ kind: GuideSectionKind, _ blocks: [GuideBlock]) {
        self.kind = kind
        self.blocks = blocks
    }
}

/// Kinds of failure a service card can show, each with a troubleshooting entry.
public enum GuideProblem: String, Sendable, Hashable, CaseIterable {
    /// 403 HTML page from the reverse proxy (VPN off, Access List, ban).
    case proxyBlocked
    /// 401: the token or password was refused.
    case tokenRejected
    /// 403 from the service, or a token that sees nothing.
    case insufficientRights
    /// No answer: VPN, DNS, certificate, port.
    case unreachable
    /// 421 Misdirected Request: one connection used for two hosts of a proxy.
    case misdirected
    /// The service answered too slowly.
    case timeout
}

public struct GuideTroubleshooting: Sendable, Hashable, Identifiable {
    /// The failure this entry explains; nil for another symptom (a 301, an
    /// empty list…).
    public let problem: GuideProblem?
    public let title: GuideText
    public let blocks: [GuideBlock]

    public var id: String { problem?.rawValue ?? title.en }

    public init(_ problem: GuideProblem?, _ title: GuideText, _ blocks: [GuideBlock]) {
        self.problem = problem
        self.title = title
        self.blocks = blocks
    }
}

public enum GuideTopic: Sendable, Hashable, Identifiable {
    case networkPrerequisites
    case service(ServiceKind)
    /// The SSH terminal (1.2): not a service type.
    case ssh

    public var id: String {
        switch self {
        case .networkPrerequisites: "network"
        case .ssh: "ssh"
        case .service(let kind): kind.rawValue
        }
    }

    /// Network prerequisites first, then every service type.
    public static let all: [GuideTopic] = [.networkPrerequisites] + ServiceKind.allCases.map(GuideTopic.service) + [.ssh]
}

public struct Guide: Sendable, Hashable, Identifiable {
    public let topic: GuideTopic
    public let title: GuideText
    /// One line, shown in the list of guides.
    public let summary: GuideText
    public let sections: [GuideSection]
    /// Entries of this guide; `troubleshooting(for:)` completes them with the
    /// generic ones.
    public let specificTroubleshooting: [GuideTroubleshooting]

    public var id: GuideTopic { topic }

    public init(
        topic: GuideTopic, title: GuideText, summary: GuideText,
        sections: [GuideSection], troubleshooting: [GuideTroubleshooting]
    ) {
        self.topic = topic
        self.title = title
        self.summary = summary
        self.sections = sections
        self.specificTroubleshooting = troubleshooting
    }

    /// Every entry: one per `GuideProblem` (this guide's, or the generic one),
    /// then this guide's other symptoms.
    public var troubleshooting: [GuideTroubleshooting] {
        GuideProblem.allCases.map(troubleshooting(for:)) + specificTroubleshooting.filter { $0.problem == nil }
    }

    public func troubleshooting(for problem: GuideProblem) -> GuideTroubleshooting {
        specificTroubleshooting.first { $0.problem == problem } ?? GuideLibrary.genericTroubleshooting(for: problem)
    }
}

/// All the built-in guides.
public enum GuideLibrary {
    public static let all: [Guide] = GuideTopic.all.map(guide(for:))

    public static func guide(for topic: GuideTopic) -> Guide {
        switch topic {
        case .networkPrerequisites: networkGuide
        case .ssh: sshGuide
        case .service(let kind): serviceGuide(kind)
        }
    }

    private static func serviceGuide(_ kind: ServiceKind) -> Guide {
        switch kind {
        case .proxmoxVE: proxmoxVEGuide
        case .proxmoxBackupServer: proxmoxBackupServerGuide
        case .dockerPortainer: portainerGuide
        case .dockerSocketProxy: dockerSocketProxyGuide
        case .tailscale: tailscaleGuide
        case .grafana: grafanaGuide
        case .prometheus: prometheusGuide
        case .alertmanager: alertmanagerGuide
        case .uptimeKuma: uptimeKumaGuide
        case .crowdSec: crowdSecGuide
        case .homeAssistant: homeAssistantGuide
        case .adGuardHome: adGuardHomeGuide
        case .nginxProxyManager: nginxProxyManagerGuide
        case .glances: glancesGuide
        }
    }
}

/// Shorthand for the content files.
func t(_ en: String, _ fr: String) -> GuideText {
    GuideText(en, fr)
}
