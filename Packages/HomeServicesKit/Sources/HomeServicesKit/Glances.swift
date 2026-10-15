import Foundation
import PatchNodeCore

/// Host metrics from Glances (`/api/4/all`, or `/api/3/all` for Glances 3).
public struct GlancesSummary: Sendable, Hashable {
    public struct FileSystem: Sendable, Hashable, Identifiable {
        public let mountPoint: String
        public let device: String?
        public let size: Int?
        public let used: Int?
        /// 0…100.
        public let percent: Double?
        public var id: String { mountPoint }

        public init(mountPoint: String, device: String? = nil, size: Int? = nil, used: Int? = nil, percent: Double? = nil) {
            self.mountPoint = mountPoint; self.device = device; self.size = size; self.used = used; self.percent = percent
        }
    }

    public struct Sensor: Sendable, Hashable, Identifiable {
        public let label: String
        public let value: Double
        public let unit: String?
        public var id: String { label }

        public init(label: String, value: Double, unit: String? = nil) {
            self.label = label; self.value = value; self.unit = unit
        }
    }

    public let apiVersion: Int
    public let hostname: String?
    public let system: String?
    /// 0…100.
    public let cpuPercent: Double?
    public let cpuCores: Int?
    public let memoryPercent: Double?
    public let memoryTotal: Int?
    public let memoryUsed: Int?
    public let swapPercent: Double?
    public let load1: Double?
    public let load5: Double?
    public let load15: Double?
    /// As Glances writes it, e.g. "5 days, 3:12:09".
    public let uptime: String?
    public let fileSystems: [FileSystem]
    /// Temperature sensors only.
    public let temperatures: [Sensor]

    public init(
        apiVersion: Int = 4, hostname: String? = nil, system: String? = nil, cpuPercent: Double? = nil, cpuCores: Int? = nil,
        memoryPercent: Double? = nil, memoryTotal: Int? = nil, memoryUsed: Int? = nil, swapPercent: Double? = nil,
        load1: Double? = nil, load5: Double? = nil, load15: Double? = nil, uptime: String? = nil,
        fileSystems: [FileSystem] = [], temperatures: [Sensor] = []
    ) {
        self.apiVersion = apiVersion; self.hostname = hostname; self.system = system
        self.cpuPercent = cpuPercent; self.cpuCores = cpuCores
        self.memoryPercent = memoryPercent; self.memoryTotal = memoryTotal; self.memoryUsed = memoryUsed
        self.swapPercent = swapPercent; self.load1 = load1; self.load5 = load5; self.load15 = load15
        self.uptime = uptime; self.fileSystems = fileSystems; self.temperatures = temperatures
    }

    public static let diskAlertPercent = 85.0
    public static let memoryAlertPercent = 90.0

    public var fullFileSystems: [FileSystem] {
        fileSystems.filter { ($0.percent ?? 0) >= Self.diskAlertPercent }
    }
}

/// Decodes the parts of `/all` the app uses. The payload is large (process list…):
/// unknown plugins are skipped.
struct GlancesAllPayload: Decodable {
    let summary: GlancesSummary

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let apiVersion = (decoder.userInfo[.glancesAPIVersion] as? Int) ?? 4
        let system = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("system"))
        let cpu = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("cpu"))
        let mem = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("mem"))
        let swap = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("memswap"))
        let load = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("load"))
        let core = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("core"))
        guard cpu != nil || mem != nil || load != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "not a Glances payload"))
        }
        let distro = system?.lenientString(AnyCodingKey("linux_distro"))
        let osName = system?.lenientString(AnyCodingKey("os_name"))
        let fileSystems = (try? c.decodeIfPresent(LossyArray<FileSystemEntry>.self, forKey: AnyCodingKey("fs")))?.elements ?? []
        let sensors = (try? c.decodeIfPresent(LossyArray<SensorEntry>.self, forKey: AnyCodingKey("sensors")))?.elements ?? []
        summary = GlancesSummary(
            apiVersion: apiVersion,
            hostname: system?.lenientString(AnyCodingKey("hostname")),
            system: (distro?.isEmpty ?? true) ? osName : distro,
            cpuPercent: cpu?.lenientDouble(AnyCodingKey("total")),
            cpuCores: load?.lenientInt(AnyCodingKey("cpucore")) ?? core?.lenientInt(AnyCodingKey("log")),
            memoryPercent: mem?.lenientDouble(AnyCodingKey("percent")),
            memoryTotal: mem?.lenientInt(AnyCodingKey("total")),
            memoryUsed: mem?.lenientInt(AnyCodingKey("used")),
            swapPercent: swap?.lenientDouble(AnyCodingKey("percent")),
            load1: load?.lenientDouble(AnyCodingKey("min1")),
            load5: load?.lenientDouble(AnyCodingKey("min5")),
            load15: load?.lenientDouble(AnyCodingKey("min15")),
            uptime: c.lenientString(AnyCodingKey("uptime")),
            fileSystems: fileSystems.map(\.fileSystem),
            temperatures: sensors.filter(\.isTemperature).map(\.sensor)
        )
    }

    struct FileSystemEntry: Decodable {
        let fileSystem: GlancesSummary.FileSystem

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            guard let mount = c.lenientString(AnyCodingKey("mnt_point")), !mount.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing mnt_point"))
            }
            fileSystem = GlancesSummary.FileSystem(
                mountPoint: mount,
                device: c.lenientString(AnyCodingKey("device_name")),
                size: c.lenientInt(AnyCodingKey("size")),
                used: c.lenientInt(AnyCodingKey("used")),
                percent: c.lenientDouble(AnyCodingKey("percent"))
            )
        }
    }

    struct SensorEntry: Decodable {
        let sensor: GlancesSummary.Sensor
        let isTemperature: Bool

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            guard let label = c.lenientString(AnyCodingKey("label")), let value = c.lenientDouble(AnyCodingKey("value")) else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing sensor value"))
            }
            let unit = c.lenientString(AnyCodingKey("unit"))
            let type = c.lenientString(AnyCodingKey("type")) ?? ""
            sensor = GlancesSummary.Sensor(label: label, value: value, unit: unit)
            isTemperature = type.hasPrefix("temperature") || unit == "C" || unit == "F"
        }
    }
}

extension CodingUserInfoKey {
    static let glancesAPIVersion = CodingUserInfoKey(rawValue: "glancesAPIVersion")!
}

/// Glances web server API (`glances -w`), optional Basic authentication (`--password`).
public struct GlancesClient: Sendable {
    private let baseURL: URL
    private let credential: String
    private let httpClient: any HTTPClientProtocol

    /// `credential`: `user:password` (Glances' default user is `glances`), or empty.
    public init(baseURL: URL, credential: String = "", httpClient: any HTTPClientProtocol = HTTPClient()) {
        self.baseURL = baseURL
        self.credential = credential
        self.httpClient = httpClient
    }

    public func checkConnection() async throws {
        _ = try await summary()
    }

    /// `/api/4/all`, then `/api/3/all` if the server answers 404 (Glances 3).
    public func summary() async throws -> GlancesSummary {
        do {
            return try await summary(apiVersion: 4)
        } catch ServiceProviderError.unexpectedStatus(404) {
            return try await summary(apiVersion: 3)
        }
    }

    private func summary(apiVersion: Int) async throws -> GlancesSummary {
        let url = baseURL.appending(component: "api").appending(component: String(apiVersion)).appending(component: "all")
        var headers: [String: String] = [:]
        if !credential.isEmpty {
            headers["Authorization"] = "Basic \(Data(credential.utf8).base64EncodedString())"
        }
        let data = try await httpClient.fetchOK(HTTPRequestSpec(method: .get, url: url, headers: headers))
        let decoder = JSONDecoder()
        decoder.userInfo[.glancesAPIVersion] = apiVersion
        do {
            return try decoder.decode(GlancesAllPayload.self, from: data).summary
        } catch {
            throw ServiceProviderError.decodingFailed
        }
    }
}
