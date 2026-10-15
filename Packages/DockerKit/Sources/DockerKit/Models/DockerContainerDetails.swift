import Foundation
import PatchNodeCore

/// Subset of `GET /containers/{id}/json`. Environment variables are deliberately
/// never decoded: they commonly hold passwords and API keys.
public struct DockerContainerDetails: Sendable, Hashable, Decodable {
    public struct Mount: Sendable, Hashable, Decodable {
        public let type: String?
        public let source: String?
        public let destination: String?
        public let readOnly: Bool

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            type = c.lenientString(AnyCodingKey("Type"))
            source = c.lenientString(AnyCodingKey("Source")) ?? c.lenientString(AnyCodingKey("Name"))
            destination = c.lenientString(AnyCodingKey("Destination"))
            readOnly = !(c.lenientBool(AnyCodingKey("RW")) ?? true)
        }
    }

    /// Container name without Docker's leading "/".
    public let name: String?
    public let isRunning: Bool
    public let startedAt: Date?
    public let finishedAt: Date?
    public let restartCount: Int?
    public let restartPolicy: String?
    public let isTTY: Bool
    public let healthStatus: String?
    public let healthFailingStreak: Int?
    public let oomKilled: Bool
    public let exitCode: Int?
    public let mounts: [Mount]
    public let networks: [String]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let rawName = c.lenientString(AnyCodingKey("Name"))
        name = rawName.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
        let state = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("State"))
        isRunning = state?.lenientBool(AnyCodingKey("Running")) ?? false
        startedAt = state?.lenientString(AnyCodingKey("StartedAt")).flatMap(DockerTimestamp.parse)
        finishedAt = state?.lenientString(AnyCodingKey("FinishedAt")).flatMap(DockerTimestamp.parse)
        oomKilled = state?.lenientBool(AnyCodingKey("OOMKilled")) ?? false
        exitCode = state?.lenientInt(AnyCodingKey("ExitCode"))
        let health = try? state?.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("Health"))
        healthStatus = health?.lenientString(AnyCodingKey("Status"))
        healthFailingStreak = health?.lenientInt(AnyCodingKey("FailingStreak"))

        restartCount = c.lenientInt(AnyCodingKey("RestartCount"))
        let hostConfig = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("HostConfig"))
        let policy = try? hostConfig?.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("RestartPolicy"))
        restartPolicy = policy?.lenientString(AnyCodingKey("Name"))

        let config = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("Config"))
        isTTY = config?.lenientBool(AnyCodingKey("Tty")) ?? false

        mounts = (try? c.decodeIfPresent(LossyArray<Mount>.self, forKey: AnyCodingKey("Mounts")))?.elements ?? []
        let networkSettings = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("NetworkSettings"))
        let networkKeys = try? networkSettings?.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("Networks"))
        networks = (networkKeys?.allKeys.map(\.stringValue) ?? []).sorted()
    }

    /// Docker reports "0001-01-01T00:00:00Z" for never.
    public var uptime: TimeInterval? {
        guard let startedAt, startedAt.timeIntervalSince1970 > 0 else { return nil }
        return max(0, Date.now.timeIntervalSince(startedAt))
    }
}
