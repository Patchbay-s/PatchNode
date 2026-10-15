import Foundation

/// When to ask for an App Store rating (`requestReview`): only after real,
/// positive use, never in a moment that would annoy. iOS itself shows the
/// prompt at most three times a year and may show nothing.
public struct ReviewPromptState: Sendable, Equatable, Codable {
    public static let storageKey = "reviewPromptState"

    /// Distinct days the app was opened (yyyy-MM-dd, local), the last 60 kept.
    public private(set) var usageDays: [String]
    /// The version the prompt was last requested for: at most once per version.
    public private(set) var lastPromptedVersion: String?

    public init(usageDays: [String] = [], lastPromptedVersion: String? = nil) {
        self.usageDays = usageDays
        self.lastPromptedVersion = lastPromptedVersion
    }

    public mutating func recordUse(now: Date = .now, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard !usageDays.contains(day) else { return }
        usageDays.append(day)
        if usageDays.count > 60 { usageDays.removeFirst(usageDays.count - 60) }
    }

    public mutating func markPrompted(version: String) {
        lastPromptedVersion = version
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decoded(from data: Data?) -> ReviewPromptState {
        data.flatMap { try? JSONDecoder().decode(ReviewPromptState.self, from: $0) } ?? ReviewPromptState()
    }
}

public enum ReviewPrompt {
    public static let minimumUsageDays = 5
    public static let minimumServices = 2
    /// Not right after launch…
    public static let quietAfterLaunch: TimeInterval = 120
    /// …nor right after an action (VM restart…) or an error.
    public static let quietAfterEvent: TimeInterval = 300

    public struct Moment: Sendable, Equatable {
        public var appVersion: String
        public var serviceCount: Int
        public var demoMode: Bool
        /// Any service failed during this session.
        public var sessionHadError: Bool
        public var launchedAt: Date
        /// Latest action or error of the session, if any.
        public var lastEventAt: Date?
        public var now: Date

        public init(appVersion: String, serviceCount: Int, demoMode: Bool, sessionHadError: Bool,
                    launchedAt: Date, lastEventAt: Date?, now: Date = .now) {
            self.appVersion = appVersion
            self.serviceCount = serviceCount
            self.demoMode = demoMode
            self.sessionHadError = sessionHadError
            self.launchedAt = launchedAt
            self.lastEventAt = lastEventAt
            self.now = now
        }
    }

    public static func shouldAsk(_ state: ReviewPromptState, at moment: Moment) -> Bool {
        guard !moment.demoMode, !moment.sessionHadError else { return false }
        guard state.lastPromptedVersion != moment.appVersion else { return false }
        guard state.usageDays.count >= minimumUsageDays, moment.serviceCount >= minimumServices else { return false }
        guard moment.now.timeIntervalSince(moment.launchedAt) >= quietAfterLaunch else { return false }
        if let event = moment.lastEventAt, moment.now.timeIntervalSince(event) < quietAfterEvent { return false }
        return true
    }
}
