import Foundation
import PatchNodeCore

/// One sample of `rrddata` (guest or node). Node samples use `memused`/`memtotal`
/// and `rootused`/`roottotal`; guest samples use `mem`/`maxmem` and `disk`/`maxdisk`.
/// Samples without data (common at the edges of a timeframe) keep nil fields.
public struct ProxmoxRRDPoint: Sendable, Hashable, Decodable {
    public let time: Date
    public let cpu: Double?
    public let memoryUsed: Double?
    public let memoryTotal: Double?
    public let networkIn: Double?
    public let networkOut: Double?
    public let diskRead: Double?
    public let diskWrite: Double?
    public let loadAverage: Double?
    public let ioWait: Double?

    public init(
        time: Date, cpu: Double? = nil, memoryUsed: Double? = nil, memoryTotal: Double? = nil,
        networkIn: Double? = nil, networkOut: Double? = nil, diskRead: Double? = nil,
        diskWrite: Double? = nil, loadAverage: Double? = nil, ioWait: Double? = nil
    ) {
        self.time = time; self.cpu = cpu; self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal
        self.networkIn = networkIn; self.networkOut = networkOut; self.diskRead = diskRead
        self.diskWrite = diskWrite; self.loadAverage = loadAverage; self.ioWait = ioWait
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        guard let seconds = c.lenientDouble(AnyCodingKey("time")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing time"))
        }
        time = Date(timeIntervalSince1970: seconds)
        cpu = c.lenientDouble(AnyCodingKey("cpu"))
        memoryUsed = c.lenientDouble(AnyCodingKey("mem")) ?? c.lenientDouble(AnyCodingKey("memused"))
        memoryTotal = c.lenientDouble(AnyCodingKey("maxmem")) ?? c.lenientDouble(AnyCodingKey("memtotal"))
        networkIn = c.lenientDouble(AnyCodingKey("netin"))
        networkOut = c.lenientDouble(AnyCodingKey("netout"))
        diskRead = c.lenientDouble(AnyCodingKey("diskread"))
        diskWrite = c.lenientDouble(AnyCodingKey("diskwrite"))
        loadAverage = c.lenientDouble(AnyCodingKey("loadavg"))
        ioWait = c.lenientDouble(AnyCodingKey("iowait"))
    }
}
