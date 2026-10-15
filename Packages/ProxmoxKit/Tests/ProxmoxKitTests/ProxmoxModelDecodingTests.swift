import Foundation
import Testing
@testable import ProxmoxKit
import PatchNodeCore

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

// MARK: - ProxmoxResource

@Suite("ProxmoxResource decoding")
struct ProxmoxResourceDecodingTests {
    @Test func decodesNodeFromPVE8Payload() throws {
        let node = try decode(ProxmoxResource.self, #"""
        {"id":"node/node-1","type":"node","node":"node-1","status":"online","cpu":0.0421,"maxcpu":8,
         "mem":6442450944,"maxmem":33554432000,"disk":10737418240,"maxdisk":100000000000,
         "uptime":172800,"level":"","cgroup-mode":2}
        """#)
        #expect(node.kind == .node)
        #expect(node.id == "node/node-1")
        #expect(node.node == "node-1")
        #expect(node.isOnline)
        #expect(node.cpu == 0.0421)
        #expect(node.maxCPU == 8)
        #expect(node.memory == 6_442_450_944)
        #expect(node.maxMemory == 33_554_432_000)
        #expect(node.uptime == 172_800)
        #expect(node.guestType == nil)
    }

    @Test func decodesKinds() throws {
        #expect(try decode(ProxmoxResource.self, #"{"id":"node/node-1","type":"node","node":"node-1"}"#).kind == .node)
        #expect(try decode(ProxmoxResource.self, #"{"id":"qemu/100","type":"qemu","vmid":100}"#).kind == .guest(.qemu))
        #expect(try decode(ProxmoxResource.self, #"{"id":"lxc/101","type":"lxc","vmid":101}"#).kind == .guest(.lxc))
        #expect(try decode(ProxmoxResource.self, #"{"id":"storage/node-1/local","type":"storage","storage":"local"}"#).kind == .storage)
        #expect(try decode(ProxmoxResource.self, #"{"id":"pool/prod","type":"pool","pool":"prod"}"#).kind == .other("pool"))
        #expect(try decode(ProxmoxResource.self, #"{"id":"sdn/node-1/localnetwork","type":"sdn","sdn":"localnetwork"}"#).kind == .other("sdn"))
    }

    @Test func guestTypeIsExposedForGuests() throws {
        let lxc = try decode(ProxmoxResource.self, #"{"id":"lxc/101","type":"lxc","node":"node-1","vmid":101}"#)
        #expect(lxc.guestType == .lxc)
    }

    @Test func numbersEncodedAsStringsAreDecoded() throws {
        let guest = try decode(ProxmoxResource.self, #"""
        {"id":"qemu/100","type":"qemu","node":"node-1","vmid":"100","cpu":"0.25","maxcpu":"4",
         "mem":"1073741824","maxmem":"4294967296","uptime":"3600"}
        """#)
        #expect(guest.vmid == 100)
        #expect(guest.cpu == 0.25)
        #expect(guest.maxCPU == 4)
        #expect(guest.memory == 1_073_741_824)
        #expect(guest.maxMemory == 4_294_967_296)
        #expect(guest.uptime == 3600)
    }

    @Test(arguments: [#"1"#, #""1""#, #"true"#])
    func truthyBooleanRepresentationsAreAccepted(raw: String) throws {
        let storage = try decode(ProxmoxResource.self,
            #"{"id":"storage/node-1/nfs","type":"storage","node":"node-1","storage":"nfs","shared":\#(raw),"template":\#(raw)}"#)
        #expect(storage.isShared)
        #expect(storage.isTemplate)
    }

    @Test(arguments: [#"0"#, #""0""#, #"false"#, #"null"#])
    func falsyBooleanRepresentationsAreAccepted(raw: String) throws {
        let storage = try decode(ProxmoxResource.self,
            #"{"id":"storage/node-1/local","type":"storage","node":"node-1","storage":"local","shared":\#(raw),"template":\#(raw)}"#)
        #expect(!storage.isShared)
        #expect(!storage.isTemplate)
    }

    @Test func missingFieldsDecodeAsNil() throws {
        let node = try decode(ProxmoxResource.self, #"{"id":"node/node-b","type":"node","node":"node-b","status":"offline"}"#)
        #expect(node.cpu == nil)
        #expect(node.maxCPU == nil)
        #expect(node.memory == nil)
        #expect(node.maxMemory == nil)
        #expect(node.disk == nil)
        #expect(node.uptime == nil)
        #expect(node.name == nil)
        #expect(node.vmid == nil)
        #expect(!node.isShared)
        #expect(!node.isTemplate)
        #expect(node.tags.isEmpty)
        #expect(!node.isOnline)
    }

    @Test func nullFieldsDecodeAsNil() throws {
        let guest = try decode(ProxmoxResource.self, #"""
        {"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"name":null,"status":null,
         "cpu":null,"maxcpu":null,"mem":null,"maxmem":null,"tags":null}
        """#)
        #expect(guest.name == nil)
        #expect(guest.status == nil)
        #expect(guest.cpu == nil)
        #expect(guest.maxCPU == nil)
        #expect(guest.memory == nil)
        #expect(guest.maxMemory == nil)
        #expect(guest.tags.isEmpty)
    }

    @Test func unparseableValuesDecodeAsNilInsteadOfFailing() throws {
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","vmid":100,"cpu":"n/a","maxmem":{"x":1},"mem":[1]}"#)
        #expect(guest.cpu == nil)
        #expect(guest.maxMemory == nil)
        #expect(guest.memory == nil)
    }

    // MARK: lenientInt overflow (Int(exactly:) fix)

    @Test func vmidAboveIntMaxDecodesAsNilWithoutCrashing() throws {
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":9223372036854775808,"name":"test-app"}"#)
        #expect(guest.vmid == nil)
        #expect(guest.kind == .guest(.qemu))
        #expect(guest.id == "qemu/100")
        #expect(guest.name == "test-app")
    }

    @Test func maxmemIntMaxAsStringDecodesAsNilWithoutCrashing() throws {
        // Double("9223372036854775807") rounds up to 2^63, which does not fit in Int.
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"maxmem":"9223372036854775807","mem":1024}"#)
        #expect(guest.maxMemory == nil)
        #expect(guest.memory == 1024)
        #expect(guest.vmid == 100)
        #expect(guest.kind == .guest(.qemu))
    }

    @Test func hugeMemDecodesAsNilWithoutCrashing() throws {
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"mem":1e300,"maxmem":4294967296}"#)
        #expect(guest.memory == nil)
        #expect(guest.maxMemory == 4_294_967_296)
        #expect(guest.memoryUsage == nil)
        #expect(guest.vmid == 100)
    }

    @Test func hugeNegativeUptimeDecodesAsNilWithoutCrashing() throws {
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"uptime":-1e300,"status":"running"}"#)
        #expect(guest.uptime == nil)
        #expect(guest.isRunning)
        #expect(guest.vmid == 100)
    }

    @Test func largeRealisticMaxmemDecodesExactly() throws {
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"maxmem":68719476736}"#)
        #expect(guest.maxMemory == 68_719_476_736)
    }

    @Test func fractionalUptimeIsTruncatedTowardZero() throws {
        let guest = try decode(ProxmoxResource.self,
            #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"uptime":12.9}"#)
        #expect(guest.uptime == 12)
    }

    @Test func fallbackIDIsBuiltWhenIDIsMissing() throws {
        let guest = try decode(ProxmoxResource.self, #"{"type":"qemu","node":"node-1","vmid":100}"#)
        #expect(guest.id == "qemu/node-1/100")
        let storage = try decode(ProxmoxResource.self, #"{"type":"storage","node":"node-1","storage":"local-lvm"}"#)
        #expect(storage.id == "storage/node-1/local-lvm")
        let node = try decode(ProxmoxResource.self, #"{"type":"node","node":"node-1"}"#)
        #expect(node.id == "node/node-1")
    }

    @Test func missingTypeFailsDecoding() {
        #expect(throws: DecodingError.self) {
            _ = try decode(ProxmoxResource.self, #"{"id":"qemu/100","vmid":100}"#)
        }
    }

    @Test func tagsAreSplitOnSemicolon() throws {
        let guest = try decode(ProxmoxResource.self, #"{"id":"qemu/100","type":"qemu","vmid":100,"tags":"prod;web;backup"}"#)
        #expect(guest.tags == ["prod", "web", "backup"])
    }

    @Test func emptyTagSegmentsAreDropped() throws {
        let guest = try decode(ProxmoxResource.self, #"{"id":"qemu/100","type":"qemu","vmid":100,"tags":";prod;;web;"}"#)
        #expect(guest.tags == ["prod", "web"])
    }

    @Test func templateFlagIsDecoded() throws {
        let template = try decode(ProxmoxResource.self,
            #"{"id":"qemu/9000","type":"qemu","node":"node-1","vmid":9000,"name":"test-vm-template","template":1}"#)
        #expect(template.isTemplate)
        let regular = try decode(ProxmoxResource.self, #"{"id":"qemu/100","type":"qemu","node":"node-1","vmid":100,"template":0}"#)
        #expect(!regular.isTemplate)
    }

    @Test func memoryAndDiskUsageRatios() throws {
        let guest = try decode(ProxmoxResource.self, #"""
        {"id":"qemu/100","type":"qemu","vmid":100,"mem":1073741824,"maxmem":4294967296,
         "disk":25000000000,"maxdisk":100000000000}
        """#)
        #expect(guest.memoryUsage == 0.25)
        #expect(guest.diskUsage == 0.25)
    }

    @Test func usageIsNilWhenTotalIsMissingOrZero() throws {
        let guest = try decode(ProxmoxResource.self, #"{"id":"qemu/100","type":"qemu","vmid":100,"mem":1024,"maxmem":0,"disk":10}"#)
        #expect(guest.memoryUsage == nil)
        #expect(guest.diskUsage == nil)
    }

    @Test func runningStatusIsDetected() throws {
        let running = try decode(ProxmoxResource.self, #"{"id":"lxc/200","type":"lxc","vmid":200,"status":"running"}"#)
        let stopped = try decode(ProxmoxResource.self, #"{"id":"lxc/201","type":"lxc","vmid":201,"status":"stopped"}"#)
        #expect(running.isRunning)
        #expect(!stopped.isRunning)
    }
}

// MARK: - LossyArray

@Suite("LossyArray decoding")
struct LossyArrayDecodingTests {
    @Test func clusterResourcesWithOneMalformedElementKeepsTheOthers() throws {
        let envelope = try decode(ProxmoxEnvelope<LossyArray<ProxmoxResource>>.self, #"""
        {"data":[
          {"id":"node/node-1","type":"node","node":"node-1","status":"online"},
          {"id":"qemu/100","node":"node-1","vmid":100,"name":"no-type"},
          {"id":"qemu/101","type":"qemu","node":"node-1","vmid":101,"name":"test-database"},
          {"id":"lxc/200","type":"lxc","node":"node-1","vmid":200,"name":"dns"}
        ]}
        """#)
        #expect(envelope.data?.elements.map(\.id) == ["node/node-1", "qemu/101", "lxc/200"])
    }

    @Test func nonObjectElementsAreSkipped() throws {
        let envelope = try decode(ProxmoxEnvelope<LossyArray<ProxmoxResource>>.self, #"""
        {"data":[null, 42, "qemu/100", {"id":"lxc/200","type":"lxc","vmid":200}, [1,2], true]}
        """#)
        #expect(envelope.data?.elements.map(\.id) == ["lxc/200"])
    }

    @Test func nullDataDecodesAsNilEnvelope() throws {
        let envelope = try decode(ProxmoxEnvelope<LossyArray<ProxmoxResource>>.self, #"{"data":null}"#)
        #expect(envelope.data == nil)
    }
}

// MARK: - ProxmoxNodeStatus

@Suite("ProxmoxNodeStatus decoding")
struct ProxmoxNodeStatusDecodingTests {
    private static let base = #"""
    "cpu":0.0421,"uptime":172800,"wait":0.0012,
    "pveversion":"pve-manager/8.2.4/faa83925c9641325",
    "kversion":"Linux 6.8.8-2-pve #1 SMP PREEMPT_DYNAMIC PMX 6.8.8-2 (2024-06-24T09:00Z)",
    "memory":{"used":5368709120,"total":33554432000,"free":28185722880},
    "rootfs":{"used":10737418240,"total":100000000000,"avail":89262581760,"free":89262581760},
    "swap":{"used":0,"total":8589934592,"free":8589934592},
    "cpuinfo":{"cpus":8,"model":"Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz","sockets":1,"cores":6,"mhz":"2100.000"}
    """#

    @Test func decodesNestedObjectsAndLoadAverageAsStrings() throws {
        let status = try decode(ProxmoxNodeStatus.self, "{\(Self.base),\"loadavg\":[\"0.12\",\"0.20\",\"0.18\"]}")
        #expect(status.cpu == 0.0421)
        #expect(status.uptime == 172_800)
        #expect(status.pveVersion == "pve-manager/8.2.4/faa83925c9641325")
        #expect(status.kernelVersion?.hasPrefix("Linux 6.8.8-2-pve") == true)
        #expect(status.memoryUsed == 5_368_709_120)
        #expect(status.memoryTotal == 33_554_432_000)
        #expect(status.rootUsed == 10_737_418_240)
        #expect(status.rootTotal == 100_000_000_000)
        #expect(status.cpuCount == 8)
        #expect(status.cpuModel == "Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz")
        #expect(status.loadAverage == [0.12, 0.20, 0.18])
    }

    @Test func decodesLoadAverageAsNumbers() throws {
        let status = try decode(ProxmoxNodeStatus.self, "{\(Self.base),\"loadavg\":[0.12,0.2,0.18]}")
        #expect(status.loadAverage == [0.12, 0.2, 0.18])
    }

    @Test func nestedNumbersAsStringsAreDecoded() throws {
        let status = try decode(ProxmoxNodeStatus.self, #"""
        {"memory":{"used":"1024","total":"4096"},"cpuinfo":{"cpus":"4"},"cpu":"0.5"}
        """#)
        #expect(status.memoryUsed == 1024)
        #expect(status.memoryTotal == 4096)
        #expect(status.cpuCount == 4)
        #expect(status.cpu == 0.5)
    }

    @Test func missingNestedObjectsDecodeAsNil() throws {
        let status = try decode(ProxmoxNodeStatus.self, #"{"cpu":0.1}"#)
        #expect(status.memoryUsed == nil)
        #expect(status.memoryTotal == nil)
        #expect(status.rootUsed == nil)
        #expect(status.rootTotal == nil)
        #expect(status.cpuCount == nil)
        #expect(status.cpuModel == nil)
        #expect(status.uptime == nil)
        #expect(status.loadAverage.isEmpty)
    }

    @Test func nullNestedObjectsDecodeAsNil() throws {
        let status = try decode(ProxmoxNodeStatus.self, #"{"memory":null,"rootfs":null,"cpuinfo":null,"loadavg":null}"#)
        #expect(status.memoryUsed == nil)
        #expect(status.rootTotal == nil)
        #expect(status.cpuCount == nil)
        #expect(status.loadAverage.isEmpty)
    }
}

// MARK: - ProxmoxGuestStatus

@Suite("ProxmoxGuestStatus decoding")
struct ProxmoxGuestStatusDecodingTests {
    @Test func decodesQemuStatusCurrentWithHAState() throws {
        let status = try decode(ProxmoxGuestStatus.self, #"""
        {"status":"running","qmpstatus":"running","name":"test-app","vmid":100,"cpu":0.12,"cpus":2,
         "mem":2147483648,"maxmem":4294967296,"disk":0,"maxdisk":34359738368,"uptime":3600,
         "netin":123456,"netout":654321,"diskread":1000,"diskwrite":2000,
         "ha":{"managed":1,"state":"started","group":"prod"}}
        """#)
        #expect(status.status == "running")
        #expect(status.isRunning)
        #expect(status.name == "test-app")
        #expect(status.vmid == 100)
        #expect(status.cpu == 0.12)
        #expect(status.cpus == 2)
        #expect(status.memory == 2_147_483_648)
        #expect(status.maxMemory == 4_294_967_296)
        #expect(status.maxDisk == 34_359_738_368)
        #expect(status.uptime == 3600)
        #expect(status.networkIn == 123_456)
        #expect(status.networkOut == 654_321)
        #expect(status.diskRead == 1000)
        #expect(status.diskWrite == 2000)
        #expect(status.haState == "started")
        #expect(status.lock == nil)
    }

    @Test func unmanagedHAHasNoState() throws {
        let status = try decode(ProxmoxGuestStatus.self, #"{"status":"stopped","vmid":"200","ha":{"managed":0}}"#)
        #expect(status.haState == nil)
        #expect(status.vmid == 200)
        #expect(!status.isRunning)
    }

    @Test func missingAndNullFieldsDecodeAsNil() throws {
        let status = try decode(ProxmoxGuestStatus.self, #"{"status":"stopped","name":null,"ha":null,"lock":"backup"}"#)
        #expect(status.name == nil)
        #expect(status.haState == nil)
        #expect(status.cpu == nil)
        #expect(status.memory == nil)
        #expect(status.lock == "backup")
    }
}

// MARK: - ProxmoxRRDPoint

@Suite("ProxmoxRRDPoint decoding")
struct ProxmoxRRDPointDecodingTests {
    @Test func decodesNodeStyleMemoryFields() throws {
        let point = try decode(ProxmoxRRDPoint.self, #"""
        {"time":1719300000,"cpu":0.04,"memused":5368709120,"memtotal":33554432000,
         "loadavg":0.2,"iowait":0.001,"netin":1500.5,"netout":800.25,"rootused":10737418240,"roottotal":100000000000}
        """#)
        #expect(point.time == Date(timeIntervalSince1970: 1_719_300_000))
        #expect(point.cpu == 0.04)
        #expect(point.memoryUsed == 5_368_709_120)
        #expect(point.memoryTotal == 33_554_432_000)
        #expect(point.loadAverage == 0.2)
        #expect(point.ioWait == 0.001)
        #expect(point.networkIn == 1500.5)
        #expect(point.networkOut == 800.25)
    }

    @Test func decodesGuestStyleMemoryFields() throws {
        let point = try decode(ProxmoxRRDPoint.self, #"""
        {"time":1719900000,"cpu":0.05,"mem":268435456,"maxmem":536870912,"disk":0,"maxdisk":8589934592,
         "diskread":1024,"diskwrite":2048,"netin":10.5,"netout":3.2,"maxcpu":2}
        """#)
        #expect(point.memoryUsed == 268_435_456)
        #expect(point.memoryTotal == 536_870_912)
        #expect(point.diskRead == 1024)
        #expect(point.diskWrite == 2048)
        #expect(point.loadAverage == nil)
    }

    @Test func sampleWithoutDataKeepsNilFields() throws {
        let point = try decode(ProxmoxRRDPoint.self, #"{"time":"1719900060"}"#)
        #expect(point.time == Date(timeIntervalSince1970: 1_719_900_060))
        #expect(point.cpu == nil)
        #expect(point.memoryUsed == nil)
        #expect(point.memoryTotal == nil)
    }

    @Test func pointsWithoutTimeAreDroppedFromList() throws {
        let envelope = try decode(ProxmoxEnvelope<LossyArray<ProxmoxRRDPoint>>.self, #"""
        {"data":[
          {"time":1719900000,"cpu":0.05},
          {"cpu":0.99,"mem":1},
          {"time":null,"cpu":0.5},
          {"time":1719900060,"cpu":0.06}
        ]}
        """#)
        let times = envelope.data?.elements.map(\.time.timeIntervalSince1970)
        #expect(times == [1_719_900_000, 1_719_900_060])
    }
}

// MARK: - ProxmoxTask

@Suite("ProxmoxTask decoding and state")
struct ProxmoxTaskDecodingTests {
    private static let now = Date(timeIntervalSince1970: 1_719_930_000)

    private func task(_ fields: String) throws -> ProxmoxTask {
        try decode(ProxmoxTask.self,
            #"{"upid":"UPID:pve:0000A1B2:00C3D4E5:66840000:vzdump:100:root@pam:","node":"node-1","type":"vzdump","id":"100","user":"root@pam""#
            + (fields.isEmpty ? "" : ",\(fields)") + "}")
    }

    @Test func decodesTaskFields() throws {
        let t = try task(#""starttime":1719926784,"endtime":1719926900,"status":"OK""#)
        #expect(t.id == "UPID:pve:0000A1B2:00C3D4E5:66840000:vzdump:100:root@pam:")
        #expect(t.node == "node-1")
        #expect(t.type == "vzdump")
        #expect(t.targetID == "100")
        #expect(t.user == "root@pam")
        #expect(t.startTime == Date(timeIntervalSince1970: 1_719_926_784))
        #expect(t.endTime == Date(timeIntervalSince1970: 1_719_926_900))
    }

    @Test func statusOKIsOk() throws {
        let t = try task(#""starttime":1719926784,"endtime":1719926900,"status":"OK""#)
        #expect(t.state == .ok)
        #expect(!t.isFailed)
    }

    @Test func warningsStatusIsWarning() throws {
        let t = try task(#""starttime":1719926784,"endtime":1719926900,"status":"WARNINGS: 1""#)
        #expect(t.state == .warning("WARNINGS: 1"))
        #expect(!t.isFailed)
    }

    @Test func missingStatusWithoutEndTimeIsRunning() throws {
        let t = try task(#""starttime":1719926784"#)
        #expect(t.state == .running)
        #expect(!t.isFailed)
    }

    @Test func emptyStatusWithoutEndTimeIsRunning() throws {
        let t = try task(#""starttime":1719926784,"status":"""#)
        #expect(t.rawStatus == nil)
        #expect(t.state == .running)
    }

    @Test func otherStatusMessageIsFailed() throws {
        let message = "command 'vzdump 100 --storage backup-nfs' failed: exit code 255"
        let t = try task(#""starttime":1719926784,"endtime":1719926900,"status":"\#(message)""#)
        #expect(t.state == .failed(message))
        #expect(t.isFailed)
    }

    @Test func emptyTargetIDIsNil() throws {
        let t = try decode(ProxmoxTask.self,
            #"{"upid":"UPID:pve:00001234:0000ABCD:66840000:aptupdate::root@pam:","type":"aptupdate","id":"","status":"OK","endtime":1}"#)
        #expect(t.targetID == nil)
    }

    @Test func missingTypeDefaultsToUnknown() throws {
        let t = try decode(ProxmoxTask.self, #"{"upid":"UPID:pve:1:2:3:x::root@pam:"}"#)
        #expect(t.type == "unknown")
    }

    @Test func missingUPIDFailsDecoding() {
        #expect(throws: DecodingError.self) {
            _ = try decode(ProxmoxTask.self, #"{"node":"node-1","type":"vzdump","status":"OK"}"#)
        }
    }

    @Test func numericFieldsAsStringsAreDecoded() throws {
        let t = try task(#""starttime":"1719926784","endtime":"1719926900","status":"OK""#)
        #expect(t.startTime == Date(timeIntervalSince1970: 1_719_926_784))
        #expect(t.endTime == Date(timeIntervalSince1970: 1_719_926_900))
    }

    @Test func durationOfFinishedTaskIsEndMinusStart() throws {
        let t = try task(#""starttime":1719926784,"endtime":1719926900,"status":"OK""#)
        #expect(t.duration(now: Self.now) == 116)
    }

    @Test func durationOfRunningTaskUsesNow() throws {
        let t = try task(#""starttime":1719929000"#)
        #expect(t.duration(now: Self.now) == 1000)
    }

    @Test func durationIsNilWithoutStartTime() throws {
        let t = try task(#""status":"OK""#)
        #expect(t.duration(now: Self.now) == nil)
    }

    @Test func durationIsNeverNegative() throws {
        let t = try task(#""starttime":1719926900,"endtime":1719926784,"status":"OK""#)
        #expect(t.duration(now: Self.now) == 0)
    }
}
