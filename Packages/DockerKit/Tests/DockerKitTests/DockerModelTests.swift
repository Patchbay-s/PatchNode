import Foundation
import Testing
import PatchNodeCore
@testable import DockerKit

private typealias F = DockerFixtures

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func container(state: String, status: String) throws -> DockerContainer {
    try decode(DockerContainer.self, #"{"Id": "abc123", "Names": ["/web"], "State": "\#(state)", "Status": "\#(status)"}"#)
}

@Suite struct DockerContainerDecodingTests {
    @Test func listDropsMalformedContainerWithoutId() throws {
        let list = try decode(LossyArray<DockerContainer>.self, F.containers).elements
        #expect(list.count == 3)
        #expect(list.map(\.name) == ["traefik", "backup-job", "ffeeddccbbaa"])
        #expect(!list.contains { $0.name == "broken" })
    }

    @Test func nominalContainerFields() throws {
        let traefik = try #require(decode(LossyArray<DockerContainer>.self, F.containers).elements.first)
        #expect(traefik.id == F.containerID)
        #expect(traefik.name == "traefik")
        #expect(traefik.image == "traefik:v3.1")
        #expect(traefik.state == .running)
        #expect(traefik.isRunning)
        #expect(traefik.status == "Up 3 hours (healthy)")
        #expect(traefik.created == Date(timeIntervalSince1970: 1_714_557_600))
        #expect(traefik.composeProject == "proxy")
        #expect(traefik.composeService == "service-04")
        #expect(traefik.labels["com.docker.compose.version"] == "2.27.0")
    }

    @Test func createdAcceptsStringTimestamp() throws {
        let backup = try decode(LossyArray<DockerContainer>.self, F.containers).elements[1]
        #expect(backup.created == Date(timeIntervalSince1970: 1_714_471_200))
    }

    @Test func portsAreDecoded() throws {
        let traefik = try #require(decode(LossyArray<DockerContainer>.self, F.containers).elements.first)
        #expect(traefik.ports == [
            DockerPort(ip: "0.0.0.0", privatePort: 443, publicPort: 443, type: "tcp"),
            DockerPort(ip: "::", privatePort: 443, publicPort: 443, type: "tcp"),
            DockerPort(ip: nil, privatePort: 8080, publicPort: nil, type: "tcp"),
            DockerPort(ip: "0.0.0.0", privatePort: 53, publicPort: 5353, type: "udp"),
        ])
    }

    @Test func portTypeDefaultsToTCPAndStringPortsAreAccepted() throws {
        let port = try decode(DockerPort.self, #"{"PrivatePort": "9000", "PublicPort": "19000"}"#)
        #expect(port == DockerPort(ip: nil, privatePort: 9000, publicPort: 19000, type: "tcp"))
    }

    @Test func nameStripsLeadingSlash() throws {
        let c = try decode(DockerContainer.self, #"{"Id": "abc", "Names": ["/grafana", "/other/alias"]}"#)
        #expect(c.name == "grafana")
    }

    @Test func nameWithoutSlashIsKept() throws {
        let c = try decode(DockerContainer.self, #"{"Id": "abc", "Names": ["grafana"]}"#)
        #expect(c.name == "grafana")
    }

    @Test(arguments: [#""Names": []"#, #""Names": ["/"]"#, #""Names": null"#, #""Other": 1"#])
    func nameFallsBackTo12CharacterID(namesFragment: String) throws {
        let c = try decode(DockerContainer.self, #"{"Id": "\#(F.containerID)", \#(namesFragment)}"#)
        #expect(c.name == "8dfafdbc3a40")
    }

    @Test func missingOrEmptyIdIsRejected() {
        #expect(throws: DecodingError.self) { try decode(DockerContainer.self, #"{"Names": ["/web"]}"#) }
        #expect(throws: DecodingError.self) { try decode(DockerContainer.self, #"{"Id": "", "Names": ["/web"]}"#) }
    }

    @Test func missingOptionalFieldsUseDefaults() throws {
        let c = try decode(DockerContainer.self, #"{"Id": "abc"}"#)
        #expect(c.image == "")
        #expect(c.status == "")
        #expect(c.state == .other(""))
        #expect(c.created == nil)
        #expect(c.ports.isEmpty)
        #expect(c.labels.isEmpty)
        #expect(c.composeProject == nil)
        #expect(c.composeService == nil)
    }

    @Test(arguments: [
        ("running", DockerContainer.State.running), ("paused", .paused), ("restarting", .restarting),
        ("exited", .exited), ("created", .created), ("dead", .dead), ("removing", .removing),
        ("Running", .running), ("EXITED", .exited), ("zombie", .other("zombie")),
    ])
    func stateIsParsed(raw: String, expected: DockerContainer.State) throws {
        #expect(try container(state: raw, status: "").state == expected)
    }

    @Test(arguments: [
        ("Up 3 hours (healthy)", DockerContainer.Health.healthy),
        ("Up 5 minutes (unhealthy)", .unhealthy),
        ("Up 10 seconds (health: starting)", .starting),
        ("Up 2 days", .none),
        ("Exited (0) 2 days ago", .none),
        ("", .none),
    ])
    func healthIsParsedFromStatus(status: String, expected: DockerContainer.Health) throws {
        #expect(try container(state: "running", status: status).health == expected)
    }

    @Test func exitCodeIsParsedFromExitedStatus() throws {
        let killed = try container(state: "exited", status: "Exited (137) 3 hours ago")
        #expect(killed.exitCode == 137)
        #expect(killed.exitedWithError)

        let clean = try container(state: "exited", status: "Exited (0) 2 days ago")
        #expect(clean.exitCode == 0)
        #expect(!clean.exitedWithError)
    }

    @Test func exitCodeIsNilWhenNotExited() throws {
        let restarting = try container(state: "restarting", status: "Restarting (1) 5 seconds ago")
        #expect(restarting.exitCode == nil)
        #expect(!restarting.exitedWithError)

        let running = try container(state: "running", status: "Up 3 hours (healthy)")
        #expect(running.exitCode == nil)
        #expect(!running.exitedWithError)
    }

    @Test func exitCodeIsNilOnUnparsableStatus() throws {
        #expect(try container(state: "exited", status: "Exited").exitCode == nil)
        #expect(try container(state: "exited", status: "Exited (abc) 1 hour ago").exitCode == nil)
        #expect(try container(state: "exited", status: "Exited (").exitCode == nil)
    }

    @Test func emptyComposeProjectLabelMeansStandalone() throws {
        let c = try decode(DockerContainer.self, #"{"Id": "abc", "Labels": {"com.docker.compose.project": ""}}"#)
        #expect(c.composeProject == nil)
    }
}

@Suite struct DockerContainerDetailsTests {
    @Test func stateFieldsAreDecoded() throws {
        let details = try decode(DockerContainerDetails.self, F.details)
        let expectedStart = Date(timeIntervalSince1970: 1_714_557_600.123456789)
        let startedAt = try #require(details.startedAt)
        #expect(abs(startedAt.timeIntervalSince(expectedStart)) < 1e-5)
        #expect(details.name == "traefik")
        #expect(details.restartCount == 2)
        #expect(details.restartPolicy == "unless-stopped")
        #expect(details.isTTY)
        #expect(details.healthStatus == "unhealthy")
        #expect(details.healthFailingStreak == 3)
        #expect(!details.oomKilled)
        #expect(details.exitCode == 0)
    }

    @Test func uptimeIsPositiveForARealStart() throws {
        let details = try decode(DockerContainerDetails.self, F.details)
        let uptime = try #require(details.uptime)
        #expect(uptime > 0)
    }

    @Test func zeroDateMeansNeverStarted() throws {
        let json = #"{"State": {"StartedAt": "0001-01-01T00:00:00Z", "FinishedAt": "0001-01-01T00:00:00Z"}}"#
        let details = try decode(DockerContainerDetails.self, json)
        #expect(details.uptime == nil)
    }

    @Test func finishedAtZeroDateParsesButIsBeforeEpoch() throws {
        let details = try decode(DockerContainerDetails.self, F.details)
        let finished = try #require(details.finishedAt)
        #expect(finished.timeIntervalSince1970 < 0)
    }

    @Test func mountsAreDecoded() throws {
        let details = try decode(DockerContainerDetails.self, F.details)
        #expect(details.mounts.count == 2)
        let bind = details.mounts[0]
        #expect(bind.type == "bind")
        #expect(bind.source == "/srv/traefik")
        #expect(bind.destination == "/etc/traefik")
        #expect(bind.readOnly)
        let volume = details.mounts[1]
        #expect(volume.type == "volume")
        #expect(volume.destination == "/certs")
        #expect(!volume.readOnly)
        // Source is "" for this volume; the fallback to Name only applies when Source is absent.
        #expect(volume.source == "")
    }

    @Test func volumeWithoutSourceFallsBackToName() throws {
        let json = #"{"Mounts": [{"Type": "volume", "Name": "pgdata", "Destination": "/var/lib/postgresql/data"}]}"#
        let details = try decode(DockerContainerDetails.self, json)
        #expect(details.mounts.first?.source == "pgdata")
        #expect(details.mounts.first?.readOnly == false)
    }

    @Test func networksAreSorted() throws {
        let details = try decode(DockerContainerDetails.self, F.details)
        #expect(details.networks == ["bridge", "monitoring", "proxy_default"])
    }

    @Test func environmentVariablesAreIgnored() throws {
        let details = try decode(DockerContainerDetails.self, F.details)
        let described = String(reflecting: details) + "\(details)"
        var mirrorDump = ""
        dump(details, to: &mirrorDump)
        for text in [described, mirrorDump] {
            #expect(!text.contains("fake-password-do-not-leak"))
            #expect(!text.contains("fake-token-1234"))
            #expect(!text.contains("POSTGRES_PASSWORD"))
        }
        let labels = Mirror(reflecting: details).children.compactMap(\.label)
        #expect(!labels.contains { $0.lowercased().contains("env") })
    }

    @Test func emptyObjectDecodesWithDefaults() throws {
        let details = try decode(DockerContainerDetails.self, "{}")
        #expect(details.startedAt == nil)
        #expect(details.uptime == nil)
        #expect(details.restartPolicy == nil)
        #expect(!details.isTTY)
        #expect(details.healthStatus == nil)
        #expect(details.mounts.isEmpty)
        #expect(details.networks.isEmpty)
    }

    @Test func oomKilledAndExitCodeAreDecoded() throws {
        let json = #"{"State": {"Status": "exited", "OOMKilled": true, "ExitCode": 137}, "Config": {"Tty": false}}"#
        let details = try decode(DockerContainerDetails.self, json)
        #expect(details.oomKilled)
        #expect(details.exitCode == 137)
        #expect(!details.isTTY)
    }
}

@Suite struct DockerStatsTests {
    @Test func cpuPercentUsesDockerFormula() throws {
        let stats = try decode(DockerStats.self, F.stats)
        // (1_250_000_000 − 1_000_000_000) / (400e9 − 398e9) × 4 × 100 = 50 %
        let cpu = try #require(stats.cpuPercent)
        #expect(abs(cpu - 50) < 1e-9)
    }

    @Test func cpuFallsBackToPercpuCountWhenOnlineCPUsMissing() throws {
        let json = """
        {"cpu_stats": {"cpu_usage": {"total_usage": 300, "percpu_usage": [100, 100, 50, 50, 0, 0, 0, 0]}, "system_cpu_usage": 2000},
         "precpu_stats": {"cpu_usage": {"total_usage": 200}, "system_cpu_usage": 1000}}
        """
        let stats = try decode(DockerStats.self, json)
        #expect(stats.onlineCPUs == 8)
        // 100 / 1000 × 8 × 100 = 80 %
        #expect(abs((stats.cpuPercent ?? -1) - 80) < 1e-9)
    }

    @Test func cpuDefaultsToOneCPUWhenCountUnknown() throws {
        let json = """
        {"cpu_stats": {"cpu_usage": {"total_usage": 300}, "system_cpu_usage": 2000},
         "precpu_stats": {"cpu_usage": {"total_usage": 200}, "system_cpu_usage": 1000}}
        """
        let stats = try decode(DockerStats.self, json)
        #expect(stats.onlineCPUs == nil)
        #expect(abs((stats.cpuPercent ?? -1) - 10) < 1e-9)
    }

    @Test func cpuIsNilWithoutPreviousSample() throws {
        // First sample: precpu_stats present but empty (Docker sends zeros/missing).
        let missing = """
        {"cpu_stats": {"cpu_usage": {"total_usage": 1250000000}, "system_cpu_usage": 400000000000, "online_cpus": 4},
         "precpu_stats": {"cpu_usage": {"total_usage": 0}, "throttling_data": {}}}
        """
        #expect(try decode(DockerStats.self, missing).cpuPercent == nil)

        let absent = """
        {"cpu_stats": {"cpu_usage": {"total_usage": 1250000000}, "system_cpu_usage": 400000000000, "online_cpus": 4}}
        """
        #expect(try decode(DockerStats.self, absent).cpuPercent == nil)
    }

    @Test func cpuIsNilForStoppedContainer() throws {
        // Stopped container: every counter is zero.
        let json = """
        {"read": "0001-01-01T00:00:00Z",
         "cpu_stats": {"cpu_usage": {"total_usage": 0}, "system_cpu_usage": 0, "throttling_data": {}},
         "precpu_stats": {"cpu_usage": {"total_usage": 0}, "system_cpu_usage": 0, "throttling_data": {}},
         "memory_stats": {}}
        """
        let stats = try decode(DockerStats.self, json)
        #expect(stats.cpuPercent == nil)
        #expect(stats.memoryUsed == nil)
        #expect(stats.memoryFraction == nil)
        #expect(stats.networkReceived == nil)
        #expect(stats.networkSent == nil)
    }

    @Test func cpuIsNilWhenCounterWentBackwards() {
        let stats = DockerStats(cpuTotal: 100, cpuSystem: 2000, preCPUTotal: 200, preCPUSystem: 1000, onlineCPUs: 2, memoryUsage: nil, memoryLimit: nil)
        #expect(stats.cpuPercent == nil)
    }

    @Test func memoryUsedSubtractsInactiveFileCgroupV2() throws {
        let stats = try decode(DockerStats.self, F.stats)
        #expect(stats.memoryCache == 52_428_800)
        #expect(stats.memoryUsed == 104_857_600)
        #expect(stats.memoryLimit == 1_073_741_824)
        #expect(stats.memoryFraction == 0.09765625)
    }

    @Test func memoryUsedSubtractsTotalInactiveFileCgroupV1() throws {
        let json = """
        {"memory_stats": {"usage": 209715200, "limit": 2147483648,
          "stats": {"cache": 104857600, "total_inactive_file": 52428800, "rss": 100000000}}}
        """
        let stats = try decode(DockerStats.self, json)
        // total_inactive_file wins over cache.
        #expect(stats.memoryUsed == 157_286_400)
    }

    @Test func memoryUsedFallsBackToCacheCgroupV1() throws {
        let json = #"{"memory_stats": {"usage": 209715200, "limit": 2147483648, "stats": {"cache": 104857600}}}"#
        #expect(try decode(DockerStats.self, json).memoryUsed == 104_857_600)
    }

    @Test func memoryUsedIsRawUsageWithoutCacheOrWhenCacheExceedsUsage() throws {
        let noStats = #"{"memory_stats": {"usage": 1000, "limit": 4000}}"#
        let plain = try decode(DockerStats.self, noStats)
        #expect(plain.memoryUsed == 1000)
        #expect(plain.memoryFraction == 0.25)

        let absurd = #"{"memory_stats": {"usage": 1000, "limit": 4000, "stats": {"inactive_file": 5000}}}"#
        #expect(try decode(DockerStats.self, absurd).memoryUsed == 1000)
    }

    @Test func memoryFractionIsNilWithoutPositiveLimit() {
        let zero = DockerStats(cpuTotal: nil, cpuSystem: nil, preCPUTotal: nil, preCPUSystem: nil, onlineCPUs: nil, memoryUsage: 1000, memoryLimit: 0)
        #expect(zero.memoryFraction == nil)
        let missing = DockerStats(cpuTotal: nil, cpuSystem: nil, preCPUTotal: nil, preCPUSystem: nil, onlineCPUs: nil, memoryUsage: 1000, memoryLimit: nil)
        #expect(missing.memoryFraction == nil)
    }

    @Test func networkBytesAreSummedOverInterfaces() throws {
        let stats = try decode(DockerStats.self, F.stats)
        #expect(stats.networkReceived == 1500)
        #expect(stats.networkSent == 2250)
    }

    @Test func networkIsNilWhenNoInterface() throws {
        let hostNetwork = #"{"networks": {}}"#
        let stats = try decode(DockerStats.self, hostNetwork)
        #expect(stats.networkReceived == nil)
        #expect(stats.networkSent == nil)
    }
}
