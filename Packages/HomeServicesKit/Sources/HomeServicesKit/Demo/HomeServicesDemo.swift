import Foundation
import Synchronization
import PatchNodeCore

/// Demo Home Assistant: sensors, lights, scenes and scripts. Activating a scene
/// or script is accepted and recorded (last triggered), nothing else happens.
public final class HomeAssistantDemoResponder: DemoResponder {
    private let triggered = Mutex<[String: Date]>([:])

    public init() {}

    /// Entities pinned on first use of the demo, so its screen isn't empty.
    public static let suggestedEntityIDs = [
        "sensor.living_room_temperature", "sensor.outdoor_temperature", "sensor.house_power",
        "sensor.solar_production", "binary_sensor.front_door", "light.living_room", "scene.movie_night", "script.good_night",
    ]

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        switch (request.method, request.segments) {
        case ("GET", ["api"]):
            return .json(#"{"message":"API running."}"#)
        case ("GET", ["api", "states"]):
            return .json(object: states(now: now))
        case ("POST", let p) where p.count == 4 && p[0] == "api" && p[1] == "services" && p[3] == "turn_on":
            let entity = request.body
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["entity_id"] as? String
            if let entity { triggered.withLock { $0[entity] = now } }
            return .json("[]")
        default:
            return .notFound
        }
    }

    private func states(now: Date) -> [[String: Any]] {
        let t = now.timeIntervalSince1970
        let changed = now.addingTimeInterval(-420).formatted(.iso8601)
        let triggered = triggered.withLock { $0 }
        func entity(_ id: String, _ state: String, _ name: String, unit: String? = nil, deviceClass: String? = nil,
                    extra: [String: Any] = [:]) -> [String: Any] {
            var attributes: [String: Any] = ["friendly_name": name]
            if let unit { attributes["unit_of_measurement"] = unit }
            if let deviceClass { attributes["device_class"] = deviceClass }
            attributes.merge(extra) { _, new in new }
            return ["entity_id": id, "state": state, "attributes": attributes, "last_changed": changed, "last_updated": changed]
        }
        let solar = max(0, 2_800 * sin((t.truncatingRemainder(dividingBy: 86_400) / 86_400 - 0.25) * 2 * .pi))
        return [
            entity("sensor.living_room_temperature", String(format: "%.1f", 21 + sin(t / 3_600)), "Living room temperature", unit: "°C", deviceClass: "temperature"),
            entity("sensor.bedroom_temperature", String(format: "%.1f", 19.5 + sin(t / 4_000)), "Bedroom temperature", unit: "°C", deviceClass: "temperature"),
            entity("sensor.outdoor_temperature", String(format: "%.1f", 14 + 5 * sin(t / 20_000)), "Outdoor temperature", unit: "°C", deviceClass: "temperature"),
            entity("sensor.living_room_humidity", "48", "Living room humidity", unit: "%", deviceClass: "humidity"),
            entity("sensor.house_power", String(Int(620 + 180 * sin(t / 700))), "House power", unit: "W", deviceClass: "power"),
            entity("sensor.solar_production", String(Int(solar)), "Solar production", unit: "W", deviceClass: "power"),
            entity("sensor.server_rack_power", "142", "Server rack power", unit: "W", deviceClass: "power"),
            entity("binary_sensor.front_door", "off", "Front door", deviceClass: "door"),
            entity("binary_sensor.garage_door", "on", "Garage door", deviceClass: "garage_door"),
            entity("sensor.garage_door_battery", "unavailable", "Garage door battery", unit: "%", deviceClass: "battery"),
            entity("light.living_room", "on", "Living room", extra: ["brightness": 180]),
            entity("light.kitchen", "off", "Kitchen"),
            entity("switch.coffee_machine", "off", "Coffee machine"),
            entity("scene.movie_night", triggered["scene.movie_night"].map { $0.formatted(.iso8601) } ?? changed, "Movie night"),
            entity("scene.away", triggered["scene.away"].map { $0.formatted(.iso8601) } ?? changed, "Away"),
            entity("script.good_night", "off", "Good night",
                   extra: ["last_triggered": triggered["script.good_night"].map { $0.formatted(.iso8601) as Any } ?? NSNull()]),
        ]
    }
}

/// Demo Glances host (a NAS): CPU, memory, file systems (one almost full),
/// temperatures.
public struct GlancesDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        guard request.method == "GET", request.segments == ["api", "4", "all"] else { return .notFound }
        let t = now.timeIntervalSince1970
        let cpu = 14 + 8 * sin(t / 180)
        let total = 34_359_738_368.0
        let memPercent = 58 + 4 * sin(t / 900)
        return .json(object: [
            "core": ["phys": 6, "log": 12],
            "cpu": ["total": cpu, "user": cpu * 0.7, "system": cpu * 0.3, "idle": 100 - cpu, "iowait": 0.8, "cpucore": 12],
            "load": ["min1": 1.12, "min5": 0.97, "min15": 0.88, "cpucore": 12],
            "mem": ["total": total, "used": total * memPercent / 100, "available": total * (100 - memPercent) / 100, "percent": memPercent],
            "memswap": ["total": 8_589_934_592.0, "used": 214_748_364.0, "percent": 2.5],
            "fs": [
                ["device_name": "/dev/nvme0n1p2", "fs_type": "ext4", "mnt_point": "/", "size": 500_107_862_016.0, "used": 142_000_000_000.0, "percent": 28.4],
                ["device_name": "/dev/md0", "fs_type": "btrfs", "mnt_point": "/srv/media", "size": 16_000_900_661_248.0, "used": 14_240_000_000_000.0, "percent": 89.0],
                ["device_name": "/dev/sdc1", "fs_type": "ext4", "mnt_point": "/srv/backup", "size": 4_000_787_030_016.0, "used": 2_470_000_000_000.0, "percent": 61.7],
            ],
            "sensors": [
                ["label": "Package id 0", "value": 48 + 6 * sin(t / 240), "warning": 80, "critical": 100, "unit": "C", "type": "temperature_core"],
                ["label": "nvme0 Composite", "value": 41.9, "unit": "C", "type": "temperature_hdd"],
                ["label": "sda", "value": 36, "unit": "C", "type": "temperature_hdd"],
                ["label": "cpu_fan", "value": 1_150, "unit": "R", "type": "fan_speed"],
            ],
            "system": ["os_name": "Linux", "hostname": "nas", "platform": "64bit", "linux_distro": "Debian GNU/Linux 12",
                       "os_version": "6.1.0-25-amd64", "hr_name": "Debian GNU/Linux 12 64bit"],
            "uptime": "23 days, 4:12:09",
            "version": "4.1.2",
        ])
    }
}
