import Foundation
import Synchronization
import PatchNodeCore

/// Demo Proxmox VE cluster (two nodes, VMs, containers, storages, tasks),
/// answered on the device. Power actions change the guest's state, so the demo
/// behaves like a real cluster; nothing is sent anywhere.
public final class ProxmoxDemoResponder: DemoResponder {
    struct Guest {
        let vmid: Int
        let type: String
        let name: String
        let node: String
        var running: Bool
        let cores: Int
        let memory: Int
        let disk: Int
        let tags: String
        var template = false
    }

    private struct State {
        var guests: [Guest]
        var actions: [(upid: String, node: String, type: String, vmid: Int, start: Date, ok: Bool)] = []
    }

    private static let gib = 1_073_741_824
    private let state: Mutex<State>
    private let bootedAt: Date

    public init(now: Date = .now) {
        bootedAt = now.addingTimeInterval(-19 * 86_400 - 4 * 3_600)
        let g = Self.gib
        state = Mutex(State(guests: [
            Guest(vmid: 100, type: "qemu", name: "service-01", node: "node-a", running: true, cores: 2, memory: 4 * g, disk: 32 * g, tags: "app"),
            Guest(vmid: 101, type: "qemu", name: "network-appliance", node: "node-a", running: true, cores: 2, memory: 2 * g, disk: 16 * g, tags: "network"),
            Guest(vmid: 200, type: "lxc", name: "dns-service", node: "node-a", running: true, cores: 1, memory: g / 2, disk: 4 * g, tags: "network;dns"),
            Guest(vmid: 201, type: "lxc", name: "reverse-proxy", node: "node-b", running: true, cores: 1, memory: g, disk: 8 * g, tags: "network"),
            Guest(vmid: 202, type: "lxc", name: "media-server", node: "node-b", running: true, cores: 4, memory: 4 * g, disk: 20 * g, tags: "media"),
            Guest(vmid: 102, type: "qemu", name: "desktop-01", node: "node-b", running: false, cores: 4, memory: 8 * g, disk: 80 * g, tags: ""),
            Guest(vmid: 203, type: "lxc", name: "test-guest", node: "node-a", running: false, cores: 1, memory: g / 2, disk: 4 * g, tags: "test"),
            Guest(vmid: 9000, type: "qemu", name: "linux-template", node: "node-b", running: false, cores: 2, memory: 2 * g, disk: 10 * g, tags: "", template: true),
        ]))
    }

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        var parts = request.segments
        guard parts.count >= 2, parts[0] == "api2", parts[1] == "json" else { return .notFound }
        parts.removeFirst(2)
        switch (request.method, parts) {
        case ("GET", ["version"]):
            return envelope(["version": "8.2.4", "release": "8.2", "repoid": "demo"])
        case ("GET", ["cluster", "resources"]):
            return envelope(resources(now: now))
        case ("GET", ["cluster", "tasks"]):
            return envelope(tasks(now: now))
        case ("GET", ["cluster", "backup"]):
            return envelope(backupJobs(now: now))
        case ("GET", ["cluster", "backup-info", "not-backed-up"]):
            return envelope([["vmid": 203, "name": "test-guest", "type": "lxc"]])
        case ("GET", let p) where p.count == 5 && p[0] == "nodes" && p[2] == "storage" && p[4] == "content":
            return envelope(backupArchives(node: p[1], storage: p[3], now: now))
        case ("GET", let p) where p.count == 4 && p[0] == "nodes" && p[2] == "disks" && p[3] == "list":
            return envelope(disks(node: p[1], smart: request.query["skipsmart"] != "1"))
        case ("GET", let p) where p.count == 4 && p[0] == "nodes" && p[2] == "disks" && p[3] == "zfs":
            return envelope(zfsPools(node: p[1]))
        case ("GET", let p) where p.count == 3 && p[0] == "nodes" && p[2] == "status":
            return envelope(nodeStatus(p[1], now: now))
        case ("GET", let p) where p.count == 3 && p[0] == "nodes" && p[2] == "rrddata":
            return envelope(rrd(seed: p[1] == "node-a" ? 1 : 2, timeframe: request.query["timeframe"], now: now, node: true))
        case ("GET", let p) where p.count == 6 && p[0] == "nodes" && p[4] == "status" && p[5] == "current":
            guard let guest = guest(Int(p[3])) else { return .notFound }
            return envelope(guestStatus(guest, now: now))
        case ("GET", let p) where p.count == 5 && p[0] == "nodes" && p[4] == "rrddata":
            guard let guest = guest(Int(p[3])) else { return .notFound }
            return envelope(guest.running ? rrd(seed: guest.vmid, timeframe: request.query["timeframe"], now: now, node: false) : [])
        case ("POST", let p) where p.count == 6 && p[0] == "nodes" && p[4] == "status":
            return perform(action: p[5], node: p[1], type: p[2], vmid: Int(p[3]), now: now)
        case ("GET", let p) where p.count == 5 && p[0] == "nodes" && p[2] == "tasks" && p[4] == "status":
            return envelope(["status": "stopped", "exitstatus": "OK", "upid": p[3]])
        default:
            return .notFound
        }
    }

    // MARK: - Data

    /// node-a: a failed disk in a degraded pool; node-b: a worn NVMe and a nearly full rpool.
    /// Like Proxmox: without SMART (`skipsmart=1`), health UNKNOWN and no wearout.
    private func disks(node: String, smart: Bool) -> [[String: Any]] {
        let t = 1_000_000_000_000
        func disk(_ dev: String, _ model: String, _ type: String, _ size: Int, health: String, wearout: Any, used: String) -> [String: Any] {
            ["devpath": dev, "model": model, "type": type, "size": size,
             "health": smart ? health : "UNKNOWN", "wearout": smart ? wearout : "N/A",
             "used": used, "serial": "DEMO\(dev.unicodeScalars.reduce(0) { $0 + Int($1.value) } * 37 + model.count)", "gpt": 1]
        }
        switch node {
        case "node-a":
            return [
                disk("/dev/nvme0n1", "Demo NVMe SSD 1TB", "nvme", t, health: "PASSED", wearout: 96, used: "ZFS"),
                disk("/dev/sda", "Demo HDD 4TB", "hdd", 4 * t, health: "PASSED", wearout: "N/A", used: "ZFS"),
                disk("/dev/sdb", "Demo HDD 4TB", "hdd", 4 * t, health: "FAILED", wearout: "N/A", used: "ZFS"),
            ]
        case "node-b":
            return [
                disk("/dev/nvme0n1", "Demo NVMe SSD 500GB", "nvme", t / 2, health: "PASSED", wearout: 8, used: "ZFS"),
                disk("/dev/sda", "Demo SATA SSD 1TB", "ssd", t, health: "PASSED", wearout: 99, used: "LVM"),
            ]
        default:
            return []
        }
    }

    private func zfsPools(node: String) -> [[String: Any]] {
        let t = 1_000_000_000_000
        func pool(_ name: String, _ health: String, size: Int, used: Double, frag: Int) -> [String: Any] {
            let alloc = Int(Double(size) * used)
            return ["name": name, "health": health, "size": size, "alloc": alloc, "free": size - alloc, "frag": frag, "dedup": 1.0]
        }
        switch node {
        case "node-a":
            return [pool("rpool", "ONLINE", size: 960_000_000_000, used: 0.41, frag: 12), pool("data", "DEGRADED", size: 4 * t, used: 0.62, frag: 18)]
        case "node-b":
            return [pool("rpool", "ONLINE", size: 480_000_000_000, used: 0.84, frag: 31)]
        default:
            return []
        }
    }

    private func guest(_ vmid: Int?) -> Guest? {
        state.withLock { state in state.guests.first { $0.vmid == vmid } }
    }

    private func resources(now: Date) -> [[String: Any]] {
        let g = Self.gib
        let uptime = Int(now.timeIntervalSince(bootedAt))
        let wave = Self.wave(now)
        var items: [[String: Any]] = [
            ["id": "node/node-a", "type": "node", "node": "node-a", "status": "online", "cpu": 0.18 + 0.06 * wave,
             "maxcpu": 8, "mem": 21 * g + Int(Double(g) * wave), "maxmem": 32 * g, "disk": 18 * g, "maxdisk": 94 * g, "uptime": uptime],
            ["id": "node/node-b", "type": "node", "node": "node-b", "status": "online", "cpu": 0.31 + 0.08 * wave,
             "maxcpu": 8, "mem": 26 * g, "maxmem": 32 * g, "disk": 22 * g, "maxdisk": 94 * g, "uptime": uptime - 3_600],
            ["id": "storage/node-a/local", "type": "storage", "node": "node-a", "storage": "local", "status": "available",
             "disk": 18 * g, "maxdisk": 94 * g, "shared": 0, "content": "iso,vztmpl,backup"],
            ["id": "storage/node-a/local-lvm", "type": "storage", "node": "node-a", "storage": "local-lvm", "status": "available",
             "disk": 210 * g, "maxdisk": 350 * g, "shared": 0],
            ["id": "storage/node-b/local", "type": "storage", "node": "node-b", "storage": "local", "status": "available",
             "disk": 22 * g, "maxdisk": 94 * g, "shared": 0, "content": "iso,vztmpl,backup"],
            ["id": "storage/node-a/backup", "type": "storage", "node": "node-a", "storage": "backup", "status": "available",
             "disk": 1_210 * g, "maxdisk": 2_000 * g, "shared": 1, "content": "backup", "plugintype": "nfs"],
            ["id": "storage/node-b/backup", "type": "storage", "node": "node-b", "storage": "backup", "status": "available",
             "disk": 1_210 * g, "maxdisk": 2_000 * g, "shared": 1, "content": "backup", "plugintype": "nfs"],
            ["id": "storage/node-b/local-lvm", "type": "storage", "node": "node-b", "storage": "local-lvm", "status": "available",
             "disk": 312 * g, "maxdisk": 350 * g, "shared": 0],
        ]
        for guest in state.withLock({ $0.guests }) {
            var item: [String: Any] = [
                "id": "\(guest.type)/\(guest.vmid)", "type": guest.type, "node": guest.node, "vmid": guest.vmid,
                "name": guest.name, "status": guest.running ? "running" : "stopped",
                "maxcpu": guest.cores, "maxmem": guest.memory, "maxdisk": guest.disk, "tags": guest.tags,
                "template": guest.template ? 1 : 0,
            ]
            if guest.running {
                let load = Self.load(guest.vmid, now)
                item["cpu"] = load * 0.6
                item["mem"] = Int(Double(guest.memory) * (0.35 + 0.4 * load))
                item["disk"] = Int(Double(guest.disk) * 0.45)
                item["uptime"] = uptime - guest.vmid * 60
            } else {
                item["cpu"] = 0
                item["mem"] = 0
                item["uptime"] = 0
            }
            items.append(item)
        }
        return items
    }

    private func tasks(now: Date) -> [[String: Any]] {
        let t = now.timeIntervalSince1970
        func task(_ node: String, _ type: String, _ id: String, ago: Double, duration: Double, status: String?) -> [String: Any] {
            let start = Int(t - ago)
            var item: [String: Any] = [
                "upid": "UPID:\(node):0000D3E0:00000000:\(Self.hex(start)):\(type):\(id):root@pam:",
                "node": node, "type": type, "id": id, "user": "root@pam", "starttime": start,
            ]
            if let status {
                item["status"] = status
                item["endtime"] = start + Int(duration)
            }
            return item
        }
        var list: [[String: Any]] = state.withLock { state in
            state.actions.map { action in
                let start = Int(action.start.timeIntervalSince1970)
                return [
                    "upid": action.upid, "node": action.node, "type": action.type, "id": String(action.vmid),
                    "user": "demo@pve!patchnode", "starttime": start, "endtime": start + 2, "status": "OK",
                ]
            }
        }
        list += [
            task("node-a", "vzdump", "100", ago: 3 * 3_600, duration: 412, status: "OK"),
            task("node-a", "vzdump", "101", ago: 3 * 3_600 - 420, duration: 95, status: "OK"),
            task("node-b", "vzdump", "202", ago: 3 * 3_600 - 600, duration: 1_210, status: "WARNINGS: 1"),
            task("node-b", "vzdump", "102", ago: 3 * 3_600 - 1_900, duration: 30, status: "job errors"),
            task("node-a", "vzdump", "200", ago: 27 * 3_600, duration: 64, status: "OK"),
            task("node-b", "qmigrate", "201", ago: 30 * 3_600, duration: 48, status: "OK"),
            task("node-a", "aptupdate", "", ago: 40 * 3_600, duration: 21, status: "OK"),
        ]
        return list
    }

    private func backupJobs(now: Date) -> [[String: Any]] {
        let calendar = Calendar(identifier: .gregorian)
        let tomorrow = calendar.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(3 * 3_600)
        return [
            ["id": "backup-daily", "type": "vzdump", "enabled": 1, "schedule": "03:00", "storage": "backup",
             "all": 1, "exclude": "203,9000", "mode": "snapshot", "comment": "Every night", "next-run": Int(tomorrow.timeIntervalSince1970)],
            ["id": "backup-weekly-local", "type": "vzdump", "enabled": 0, "schedule": "sun 04:00", "storage": "local",
             "vmid": "100,101", "mode": "stop", "comment": "Old local copy"],
        ]
    }

    /// Nightly archives on shared storage; one guest's last good archive is old.
    private func backupArchives(node: String, storage: String, now: Date) -> [[String: Any]] {
        guard storage == "backup" else { return [] }
        let g = Self.gib
        let tonight = Calendar(identifier: .gregorian).startOfDay(for: now).addingTimeInterval(3 * 3_600)
        let lastRun = tonight > now ? tonight.addingTimeInterval(-86_400) : tonight
        var archives: [[String: Any]] = []
        for guest in state.withLock({ $0.guests }) where !guest.template && guest.vmid != 203 {
            let kind = guest.type == "lxc" ? "lxc" : "qemu"
            let firstMissing = guest.vmid == 102 ? 4 : 0
            for day in firstMissing..<(firstMissing + 7) {
                let date = lastRun.addingTimeInterval(-Double(day) * 86_400 + Double(guest.vmid % 50) * 20)
                let stamp = Self.archiveStamp(date)
                let ext = kind == "lxc" ? "tar.zst" : "vma.zst"
                archives.append([
                    "volid": "backup:backup/vzdump-\(kind)-\(guest.vmid)-\(stamp).\(ext)",
                    "vmid": guest.vmid, "ctime": Int(date.timeIntervalSince1970),
                    "size": guest.disk / 3 + day * g / 50, "format": ext, "content": "backup",
                    "notes": "\(guest.name) (demo)", "protected": day == 0 && guest.vmid == 100 ? 1 : 0,
                ])
            }
        }
        return archives
    }

    private static func archiveStamp(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(c.year ?? 2026)_\(two(c.month))_\(two(c.day))-\(two(c.hour))_\(two(c.minute))_\(two(c.second))"
    }

    private func nodeStatus(_ node: String, now: Date) -> [String: Any] {
        let g = Self.gib
        return [
            "cpu": node == "node-a" ? 0.2 : 0.33, "uptime": Int(now.timeIntervalSince(bootedAt)),
            "pveversion": "pve-manager/8.2.4/demo", "kversion": "Linux 6.8.8-demo",
            "memory": ["used": node == "node-a" ? 21 * g : 26 * g, "total": 32 * g],
            "rootfs": ["used": 18 * g, "total": 94 * g],
            "cpuinfo": ["cpus": 8, "model": "Demo x86_64 CPU"],
            "loadavg": ["0.82", "0.95", "1.04"],
        ]
    }

    private func guestStatus(_ guest: Guest, now: Date) -> [String: Any] {
        let load = guest.running ? Self.load(guest.vmid, now) : 0
        return [
            "status": guest.running ? "running" : "stopped", "name": guest.name, "vmid": guest.vmid,
            "cpu": load * 0.6, "cpus": guest.cores, "mem": guest.running ? Int(Double(guest.memory) * (0.35 + 0.4 * load)) : 0,
            "maxmem": guest.memory, "disk": Int(Double(guest.disk) * 0.45), "maxdisk": guest.disk,
            "uptime": guest.running ? Int(now.timeIntervalSince(bootedAt)) - guest.vmid * 60 : 0,
            "netin": guest.vmid * 91_234_567, "netout": guest.vmid * 45_678_901,
            "diskread": guest.vmid * 12_345_678, "diskwrite": guest.vmid * 23_456_789,
        ]
    }

    /// Smooth, deterministic series ending now.
    private func rrd(seed: Int, timeframe: String?, now: Date, node: Bool) -> [[String: Any]] {
        let step: Double = switch timeframe {
        case "day": 1_800
        case "week": 10_800
        default: 60
        }
        let end = (now.timeIntervalSince1970 / step).rounded(.down) * step
        let phase = Double(seed % 17)
        return (0..<70).map { index -> [String: Any] in
            let time = end - Double(69 - index) * step
            let x = time / (step * 9) + phase
            let cpu = max(0.02, 0.18 + 0.12 * sin(x) + 0.05 * sin(x * 3.1))
            let total = node ? 34_359_738_368.0 : 4_294_967_296.0
            var point: [String: Any] = [
                "time": Int(time), "cpu": cpu,
                "netin": 120_000 + 90_000 * (1 + sin(x * 1.7)), "netout": 60_000 + 40_000 * (1 + cos(x * 1.3)),
                "diskread": 30_000 + 25_000 * (1 + sin(x * 0.7)), "diskwrite": 80_000 + 60_000 * (1 + cos(x * 0.9)),
            ]
            if node {
                point["memused"] = total * (0.62 + 0.05 * sin(x / 2))
                point["memtotal"] = total
                point["loadavg"] = 0.9 + 0.4 * sin(x)
                point["iowait"] = 0.01 + 0.01 * (1 + sin(x * 2))
            } else {
                point["mem"] = total * (0.45 + 0.1 * sin(x / 2))
                point["maxmem"] = total
            }
            return point
        }
    }

    private func perform(action: String, node: String, type: String, vmid: Int?, now: Date) -> DemoResponse {
        guard let vmid, let guestAction = ProxmoxGuestAction(rawValue: action) else { return .notFound }
        let upid = "UPID:\(node):0000D3E0:00000001:\(Self.hex(Int(now.timeIntervalSince1970))):\(Self.taskType(guestAction, type: type)):\(vmid):demo@pve!patchnode:"
        let found = state.withLock { state -> Bool in
            guard let index = state.guests.firstIndex(where: { $0.vmid == vmid && $0.node == node }) else { return false }
            switch guestAction {
            case .start, .reboot: state.guests[index].running = true
            case .shutdown, .stop: state.guests[index].running = false
            }
            state.actions.insert((upid, node, Self.taskType(guestAction, type: type), vmid, now, true), at: 0)
            if state.actions.count > 50 { state.actions.removeLast(state.actions.count - 50) }
            return true
        }
        return found ? envelope(upid) : .notFound
    }

    private static func taskType(_ action: ProxmoxGuestAction, type: String) -> String {
        let prefix = type == "lxc" ? "vz" : "qm"
        return prefix + action.rawValue
    }

    // MARK: - Helpers

    private func envelope(_ data: Any) -> DemoResponse {
        .json(object: ["data": data])
    }

    static func hex(_ value: Int) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }

    /// 0…1, slowly changing so successive refreshes differ a little.
    static func wave(_ now: Date) -> Double {
        (1 + sin(now.timeIntervalSince1970 / 300)) / 2
    }

    static func load(_ vmid: Int, _ now: Date) -> Double {
        let base = Double(vmid % 7) / 10
        return min(0.95, max(0.03, 0.15 + base * 0.6 + 0.1 * sin(now.timeIntervalSince1970 / 240 + Double(vmid))))
    }
}

/// Demo Proxmox Backup Server: one datastore, a backup group per demo guest (one
/// of them late), recent backup, verify and garbage collection tasks.
public struct PBSDemoResponder: DemoResponder {
    public init() {}

    public func respond(to request: DemoRequest, now: Date) -> DemoResponse {
        var parts = request.segments
        guard parts.count >= 2, parts[0] == "api2", parts[1] == "json" else { return .notFound }
        parts.removeFirst(2)
        let t = Int(now.timeIntervalSince1970)
        let g = 1_073_741_824
        switch parts {
        case ["version"]:
            return .json(object: ["data": ["version": "3.2.7", "release": "3.2"]])
        case ["admin", "datastore"]:
            return .json(object: ["data": [["store": "backups", "comment": "NAS (NFS)"]]])
        case ["admin", "datastore", "backups", "status"]:
            return .json(object: ["data": ["total": 4_000 * g, "used": 2_870 * g, "avail": 1_130 * g]])
        case ["admin", "datastore", "backups", "groups"]:
            let groups: [(String, String, Int, Int)] = [
                ("vm", "100", 3 * 3_600, 14), ("vm", "101", 3 * 3_600 - 420, 14), ("ct", "200", 27 * 3_600, 14),
                ("ct", "201", 3 * 3_600 - 300, 14), ("ct", "202", 3 * 3_600 - 600, 12), ("vm", "102", 4 * 86_400, 9),
                ("host", "node-a", 26 * 3_600, 7),
            ]
            return .json(object: ["data": groups.map { type, id, ago, count in
                ["backup-type": type, "backup-id": id, "last-backup": t - ago, "backup-count": count, "owner": "backup@pbs"]
            }])
        case ["nodes", "localhost", "tasks"]:
            func task(_ type: String, _ worker: String, ago: Int, duration: Int, status: String) -> [String: Any] {
                let start = t - ago
                return [
                    "upid": "UPID:pbs:00001A2B:00000000:\(ProxmoxDemoResponder.hex(start)):\(type):\(worker.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")):backup@pbs:",
                    "node": "pbs", "worker_type": type, "worker_id": worker, "user": "backup@pbs",
                    "starttime": start, "endtime": start + duration, "status": status,
                ]
            }
            return .json(object: ["data": [
                task("backup", "backups:vm/100", ago: 3 * 3_600, duration: 410, status: "OK"),
                task("backup", "backups:vm/101", ago: 3 * 3_600 - 420, duration: 92, status: "OK"),
                task("backup", "backups:ct/201", ago: 3 * 3_600 - 300, duration: 40, status: "OK"),
                task("backup", "backups:ct/202", ago: 3 * 3_600 - 600, duration: 1_200, status: "OK"),
                task("verificationjob", "backups:v-3f2a", ago: 9 * 3_600, duration: 1_800, status: "OK"),
                task("garbage_collection", "backups", ago: 20 * 3_600, duration: 640, status: "OK"),
                task("prune", "backups", ago: 21 * 3_600, duration: 12, status: "OK"),
            ]])
        default:
            return .notFound
        }
    }
}
