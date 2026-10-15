import Foundation
import PatchNodeCore

/// One entry of `GET /cluster/tasks`.
public struct ProxmoxTask: Sendable, Hashable, Identifiable, Decodable {
    public enum State: Sendable, Hashable {
        case running
        case ok
        case warning(String)
        case failed(String)
    }

    /// The UPID, unique across the cluster.
    public let id: String
    public let node: String?
    public let type: String
    /// Target of the task (usually a VMID), when any.
    public let targetID: String?
    public let user: String?
    public let startTime: Date?
    public let endTime: Date?
    public let rawStatus: String?

    public init(
        id: String, node: String? = nil, type: String, targetID: String? = nil, user: String? = nil,
        startTime: Date? = nil, endTime: Date? = nil, rawStatus: String? = nil
    ) {
        self.id = id; self.node = node; self.type = type; self.targetID = targetID; self.user = user
        self.startTime = startTime; self.endTime = endTime; self.rawStatus = rawStatus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let upid = c.lenientString(AnyCodingKey("upid")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing upid"))
        }
        id = upid
        node = c.lenientString(AnyCodingKey("node"))
        type = c.lenientString(AnyCodingKey("type")) ?? "unknown"
        let target = c.lenientString(AnyCodingKey("id"))
        targetID = (target?.isEmpty ?? true) ? nil : target
        user = c.lenientString(AnyCodingKey("user"))
        startTime = c.lenientDouble(AnyCodingKey("starttime")).map { Date(timeIntervalSince1970: $0) }
        endTime = c.lenientDouble(AnyCodingKey("endtime")).map { Date(timeIntervalSince1970: $0) }
        let status = c.lenientString(AnyCodingKey("status"))
        rawStatus = (status?.isEmpty ?? true) ? nil : status
    }

    public var state: State {
        guard let rawStatus else { return endTime == nil ? .running : .ok }
        if rawStatus == "OK" { return .ok }
        if rawStatus.hasPrefix("WARNINGS") { return .warning(rawStatus) }
        if rawStatus == "running" { return .running }
        return .failed(rawStatus)
    }

    public var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    public func duration(now: Date = .now) -> TimeInterval? {
        guard let startTime else { return nil }
        return max(0, (endTime ?? now).timeIntervalSince(startTime))
    }
}
