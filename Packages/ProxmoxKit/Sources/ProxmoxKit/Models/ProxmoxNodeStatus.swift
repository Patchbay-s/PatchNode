import Foundation
import PatchNodeCore

/// `GET /nodes/{node}/status`.
public struct ProxmoxNodeStatus: Sendable, Hashable, Decodable {
    public let cpu: Double?
    public let cpuCount: Int?
    public let cpuModel: String?
    public let memoryUsed: Int?
    public let memoryTotal: Int?
    public let rootUsed: Int?
    public let rootTotal: Int?
    public let uptime: Int?
    public let pveVersion: String?
    public let kernelVersion: String?
    public let loadAverage: [Double]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        cpu = c.lenientDouble(AnyCodingKey("cpu"))
        uptime = c.lenientInt(AnyCodingKey("uptime"))
        pveVersion = c.lenientString(AnyCodingKey("pveversion"))
        kernelVersion = c.lenientString(AnyCodingKey("kversion"))

        let memory = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("memory"))
        memoryUsed = memory?.lenientInt(AnyCodingKey("used"))
        memoryTotal = memory?.lenientInt(AnyCodingKey("total"))

        let rootfs = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("rootfs"))
        rootUsed = rootfs?.lenientInt(AnyCodingKey("used"))
        rootTotal = rootfs?.lenientInt(AnyCodingKey("total"))

        let cpuInfo = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("cpuinfo"))
        cpuCount = cpuInfo?.lenientInt(AnyCodingKey("cpus"))
        cpuModel = cpuInfo?.lenientString(AnyCodingKey("model"))

        // ["0.12","0.20","0.18"] or [0.12, 0.2, 0.18]
        if let strings = try? c.decodeIfPresent([String].self, forKey: AnyCodingKey("loadavg")) {
            loadAverage = strings.compactMap { Double($0) }
        } else if let numbers = try? c.decodeIfPresent([Double].self, forKey: AnyCodingKey("loadavg")) {
            loadAverage = numbers
        } else {
            loadAverage = []
        }
    }
}
