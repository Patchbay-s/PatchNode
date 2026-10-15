import Foundation
import PatchNodeCore

/// `GET /nodes/{node}/{qemu|lxc}/{vmid}/status/current`.
public struct ProxmoxGuestStatus: Sendable, Hashable, Decodable {
    public let status: String?
    public let name: String?
    public let vmid: Int?
    public let cpu: Double?
    public let cpus: Double?
    public let memory: Int?
    public let maxMemory: Int?
    public let disk: Int?
    public let maxDisk: Int?
    public let uptime: Int?
    public let networkIn: Int?
    public let networkOut: Int?
    public let diskRead: Int?
    public let diskWrite: Int?
    public let lock: String?
    public let haState: String?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        status = c.lenientString(AnyCodingKey("status"))
        name = c.lenientString(AnyCodingKey("name"))
        vmid = c.lenientInt(AnyCodingKey("vmid"))
        cpu = c.lenientDouble(AnyCodingKey("cpu"))
        cpus = c.lenientDouble(AnyCodingKey("cpus"))
        memory = c.lenientInt(AnyCodingKey("mem"))
        maxMemory = c.lenientInt(AnyCodingKey("maxmem"))
        disk = c.lenientInt(AnyCodingKey("disk"))
        maxDisk = c.lenientInt(AnyCodingKey("maxdisk"))
        uptime = c.lenientInt(AnyCodingKey("uptime"))
        networkIn = c.lenientInt(AnyCodingKey("netin"))
        networkOut = c.lenientInt(AnyCodingKey("netout"))
        diskRead = c.lenientInt(AnyCodingKey("diskread"))
        diskWrite = c.lenientInt(AnyCodingKey("diskwrite"))
        lock = c.lenientString(AnyCodingKey("lock"))
        let ha = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("ha"))
        haState = ha?.lenientString(AnyCodingKey("state"))
    }

    public var isRunning: Bool { status == "running" }
}
