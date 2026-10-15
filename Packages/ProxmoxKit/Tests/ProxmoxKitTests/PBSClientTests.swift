import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import PatchNodeCore
@testable import ProxmoxKit

// MARK: - Fixtures (shared with PBSProviderTests)

/// Realistic Proxmox Backup Server 3.x responses. Token and hosts are fake.
enum PBSFixtures {
    static let fakeToken = "test-user@pam!test-token:00000000-fake-0000-token"
    static let baseURL = URL(string: "https://pbs.example.invalid:8007")!
    static let baseURLWithTrailingSlash = URL(string: "https://pbs.example.invalid:8007/")!

    /// Two datastores; the second has an empty comment.
    static let datastoreList = #"""
    {"data":[
      {"store":"backup-main","comment":"Primary ZFS pool","maintenance":null},
      {"store":"offsite","comment":""}
    ]}
    """#

    /// 900 GB used out of 1 TB: 90 %.
    static let mainStatus = #"""
    {"data":{"total":1000000000000,"used":900000000000,"avail":100000000000,
      "gc-status":{"upid":null,"disk-bytes":0,"index-data-bytes":0},
      "counts":{"vm":{"groups":2,"snapshots":28},"ct":{"groups":1,"snapshots":14}}}}
    """#

    /// 400 GB used out of 2 TB: 20 %.
    static let offsiteStatus = #"""
    {"data":{"total":2000000000000,"used":400000000000,"avail":1600000000000}}
    """#

    static let mainGroups = #"""
    {"data":[
      {"backup-type":"vm","backup-id":"100","last-backup":1719925000,"backup-count":14,
       "owner":"root@pam","files":["index.json.blob","drive-scsi0.img.fidx"],"comment":"test-app"},
      {"backup-type":"ct","backup-id":"200","last-backup":1719700000,"backup-count":7,
       "owner":"root@pam","files":["index.json.blob","root.pxar.didx"],"comment":""},
      {"backup-type":"host","backup-id":"nas","last-backup":1719000000,"backup-count":3,
       "owner":"root@pam","files":["index.json.blob","root.pxar.didx"]}
    ]}
    """#

    static let offsiteGroups = #"""
    {"data":[
      {"backup-type":"vm","backup-id":"100","last-backup":1719900000,"backup-count":30,"owner":"sync@pbs"},
      {"backup-type":"vm","backup-id":"101","last-backup":1719928000,"backup-count":5,"owner":"sync@pbs"}
    ]}
    """#

    /// A successful backup, a failed garbage collection and a running verification.
    static let tasks = #"""
    {"data":[
      {"upid":"UPID:pbs:000012AB:0003C4D5:00000002:66840E08:backup:backup-main\\x3avm-100:root@pam!test-token:",
       "node":"pbs","pid":4779,"pstart":247000,"starttime":1719925000,"endtime":1719925300,
       "status":"OK","worker_type":"backup","worker_id":"backup-main:vm/100","user":"root@pam"},
      {"upid":"UPID:pbs:000012AC:0003C4D6:00000000:66840A00:garbage_collection:backup-main:root@pam:",
       "node":"pbs","pid":4780,"pstart":247001,"starttime":1719924000,"endtime":1719924100,
       "status":"TASK ERROR: unable to access chunk store","worker_type":"garbage_collection","worker_id":"backup-main","user":"root@pam"},
      {"upid":"UPID:pbs:000012AD:0003C4D7:00000000:66841000:verificationjob:offsite\\x3av\\x2dabc:root@pam:",
       "node":"pbs","pid":4781,"pstart":247002,"starttime":1719926000,
       "worker_type":"verificationjob","worker_id":"","user":"root@pam"}
    ]}
    """#

    static func response(_ body: String, status: Int = 200) -> FakeHTTPClient.Outcome {
        .response(status: status, body: Data(body.utf8))
    }

    /// Request order of `datastores()` for the two-store fixture.
    static let fullDatastoresSequence: [FakeHTTPClient.Outcome] = [
        response(datastoreList),
        response(mainStatus), response(mainGroups),
        response(offsiteStatus), response(offsiteGroups),
    ]
}

private func makeClient(_ fake: FakeHTTPClient, baseURL: URL = PBSFixtures.baseURL) -> PBSClient {
    PBSClient(baseURL: baseURL, apiTokenValue: PBSFixtures.fakeToken, httpClient: fake)
}

private func paths(_ fake: FakeHTTPClient) async -> [String] {
    await fake.receivedSpecs.map { $0.url.path(percentEncoded: false) }
}

// MARK: - Requests

@Suite("PBSClient requests")
struct PBSClientRequestTests {
    @Test func everyRequestIsGetWithPBSAPITokenHeader() async throws {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence + [PBSFixtures.response(PBSFixtures.tasks)])
        let client = makeClient(fake)
        _ = try await client.datastores()
        _ = try await client.tasks()
        let specs = await fake.receivedSpecs
        #expect(specs.count == 6)
        for spec in specs {
            #expect(spec.method == .get)
            #expect(spec.headers["Authorization"] == "PBSAPIToken=\(PBSFixtures.fakeToken)")
            #expect(spec.headers["Authorization"]?.hasPrefix("PVEAPIToken") == false)
            #expect(spec.url.scheme == "https")
            #expect(spec.url.host() == "pbs.example.invalid")
            #expect(spec.url.port == 8007)
        }
    }

    @Test func checkConnectionListsDatastoresOnlyOnce() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.datastoreList)
        try await makeClient(fake).checkConnection()
        #expect(await paths(fake) == ["/api2/json/admin/datastore"])
    }

    @Test func datastoresRequestsListThenStatusAndGroupsPerStoreSequentially() async throws {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence)
        _ = try await makeClient(fake).datastores()
        #expect(await paths(fake) == [
            "/api2/json/admin/datastore",
            "/api2/json/admin/datastore/backup-main/status",
            "/api2/json/admin/datastore/backup-main/groups",
            "/api2/json/admin/datastore/offsite/status",
            "/api2/json/admin/datastore/offsite/groups",
        ])
    }

    @Test func groupsTargetsStoreGroupsPath() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.mainGroups)
        _ = try await makeClient(fake).groups(in: "backup-main")
        #expect(await paths(fake) == ["/api2/json/admin/datastore/backup-main/groups"])
    }

    @Test func tasksTargetsLocalhostTasksWithDefaultLimit() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.tasks)
        _ = try await makeClient(fake).tasks()
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.path(percentEncoded: false) == "/api2/json/nodes/localhost/tasks")
        let query = URLComponents(url: spec.url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "limit", value: "50")])
    }

    @Test func tasksPassesCustomLimit() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.tasks)
        _ = try await makeClient(fake).tasks(limit: 20)
        let spec = try #require(await fake.receivedSpecs.first)
        #expect(spec.url.query() == "limit=20")
    }

    @Test func trailingSlashInBaseURLDoesNotProduceDoubleSlash() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.datastoreList)
        try await makeClient(fake, baseURL: PBSFixtures.baseURLWithTrailingSlash).checkConnection()
        let url = try #require(await fake.receivedSpecs.first?.url)
        #expect(!url.absoluteString.contains("//api2"))
        #expect(url.path(percentEncoded: false) == "/api2/json/admin/datastore")
    }
}

// MARK: - Nominal decoding

@Suite("PBSClient decoding")
struct PBSClientDecodingTests {
    @Test func datastoresCombineListStatusAndGroups() async throws {
        let fake = FakeHTTPClient(sequence: PBSFixtures.fullDatastoresSequence)
        let stores = try await makeClient(fake).datastores()
        #expect(stores.map(\.name) == ["backup-main", "offsite"])

        let main = stores[0]
        #expect(main.comment == "Primary ZFS pool")
        #expect(main.total == 1_000_000_000_000)
        #expect(main.used == 900_000_000_000)
        #expect(main.available == 100_000_000_000)
        #expect(main.usage == 0.9)
        #expect(main.groups.map(\.id) == ["vm/100", "ct/200", "host/nas"])

        let offsite = stores[1]
        #expect(offsite.comment == nil)
        #expect(offsite.usage == 0.2)
        #expect(offsite.groups.map(\.id) == ["vm/100", "vm/101"])
    }

    @Test func groupsDecodeTypeIDDateCountAndComment() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.mainGroups)
        let groups = try await makeClient(fake).groups(in: "backup-main")
        #expect(groups.count == 3)
        #expect(groups[0] == PBSBackupGroup(
            type: .vm, backupID: "100", lastBackup: Date(timeIntervalSince1970: 1_719_925_000), count: 14, comment: "test-app"
        ))
        #expect(groups[1].type == .ct)
        #expect(groups[1].comment == nil)
        #expect(groups[2].type == .host)
        #expect(groups[2].backupID == "nas")
    }

    @Test func invalidGroupEntriesAreSkippedNotFatal() async throws {
        let fake = FakeHTTPClient.json(#"""
        {"data":[
          {"backup-type":"vm","backup-id":"100","last-backup":1719925000},
          {"backup-type":"qemu","backup-id":"101","last-backup":1719925000},
          {"backup-id":"102"},
          {"backup-type":"ct","backup-id":""},
          {"backup-type":"ct","backup-id":"200"}
        ]}
        """#)
        let groups = try await makeClient(fake).groups(in: "backup-main")
        #expect(groups.map(\.id) == ["vm/100", "ct/200"])
        #expect(groups[1].lastBackup == nil)
    }

    @Test func tasksMapWorkerTypeAndWorkerIDOntoProxmoxTask() async throws {
        let fake = FakeHTTPClient.json(PBSFixtures.tasks)
        let tasks = try await makeClient(fake).tasks()
        #expect(tasks.count == 3)

        let backup = tasks[0]
        #expect(backup.id.hasPrefix("UPID:pbs:000012AB"))
        #expect(backup.node == "pbs")
        #expect(backup.type == "backup")
        #expect(backup.targetID == "backup-main:vm/100")
        #expect(backup.user == "root@pam")
        #expect(backup.startTime == Date(timeIntervalSince1970: 1_719_925_000))
        #expect(backup.endTime == Date(timeIntervalSince1970: 1_719_925_300))
        #expect(backup.state == .ok)

        let gc = tasks[1]
        #expect(gc.type == "garbage_collection")
        #expect(gc.isFailed)

        let verify = tasks[2]
        #expect(verify.targetID == nil)
        #expect(verify.rawStatus == nil)
        #expect(verify.state == .running)
    }

    @Test func taskWithoutUPIDIsSkipped() async throws {
        let fake = FakeHTTPClient.json(#"""
        {"data":[{"worker_type":"backup","starttime":1719925000},
                 {"upid":"UPID:pbs:1:2:3:4:prune:backup-main:root@pam:","worker_type":"prune","status":"OK"}]}
        """#)
        let tasks = try await makeClient(fake).tasks()
        #expect(tasks.map(\.type) == ["prune"])
    }

    @Test func taskWithoutWorkerTypeIsUnknown() async throws {
        let fake = FakeHTTPClient.json(#"{"data":[{"upid":"UPID:pbs:1:2:3:4:x::root@pam:"}]}"#)
        let tasks = try await makeClient(fake).tasks()
        #expect(tasks.first?.type == "unknown")
    }

    @Test func datastoreEntryWithoutStoreNameIsSkipped() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(#"{"data":[{"comment":"no name"},{"store":""},{"store":"offsite"}]}"#),
            PBSFixtures.response(PBSFixtures.offsiteStatus), PBSFixtures.response(PBSFixtures.offsiteGroups),
        ])
        let stores = try await makeClient(fake).datastores()
        #expect(stores.map(\.name) == ["offsite"])
        #expect(await fake.receivedSpecs.count == 3)
    }

    @Test func numbersSentAsStringsAreAccepted() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(#"{"data":[{"store":"backup-main"}]}"#),
            PBSFixtures.response(#"{"data":{"total":"1000","used":"250","avail":"750"}}"#),
            PBSFixtures.response(#"{"data":[]}"#),
        ])
        let store = try #require(try await makeClient(fake).datastores().first)
        #expect(store.total == 1000)
        #expect(store.used == 250)
        #expect(store.available == 750)
    }
}

// MARK: - Errors

@Suite("PBSClient errors")
struct PBSClientErrorTests {
    @Test func unauthorized401OnListMapsToUnauthorizedWithoutRetryOrDetails() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unauthorized))
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeClient(fake).datastores()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func forbidden403OnListMapsToForbiddenWithoutRetry() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        await #expect(throws: ServiceProviderError.forbidden) {
            try await makeClient(fake).checkConnection()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func forbidden403OnTasksMapsToForbiddenWithoutRetry() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.forbidden))
        await #expect(throws: ServiceProviderError.forbidden) {
            _ = try await makeClient(fake).tasks()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func timeoutMapsToUnreachable() async {
        let fake = FakeHTTPClient(.failure(HTTPClientError.unreachable))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake).datastores()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func rawURLErrorTimeoutMapsToUnreachable() async {
        let fake = FakeHTTPClient(.failure(URLError(.timedOut)))
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await makeClient(fake).tasks()
        }
    }

    @Test func non200StatusMapsToUnexpectedStatus() async {
        let fake = FakeHTTPClient.json(#"{"data":null,"message":"proxy error"}"#, status: 502)
        await #expect(throws: ServiceProviderError.unexpectedStatus(502)) {
            try await makeClient(fake).checkConnection()
        }
    }

    @Test(arguments: [
        "<html><body>502 Bad Gateway</body></html>",
        #"{"data":[{"store":"backup-main""#,
        #"{"data":"not a list"}"#,
        "",
    ])
    func invalidOrEmptyBodyOnListThrowsDecodingFailed(body: String) async {
        let fake = FakeHTTPClient.json(body)
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).datastores()
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func invalidJSONOnGroupsThrowsDecodingFailed() async {
        let fake = FakeHTTPClient.json("<html>not json</html>")
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).groups(in: "backup-main")
        }
    }

    @Test func invalidJSONOnTasksThrowsDecodingFailed() async {
        let fake = FakeHTTPClient(.response(status: 200, body: Data()))
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await makeClient(fake).tasks()
        }
    }

    @Test func nullOrEmptyDataOnListsReturnsEmpty() async throws {
        for body in [#"{"data":null}"#, #"{"data":[]}"#] {
            let fake = FakeHTTPClient.json(body)
            let client = makeClient(fake)
            #expect(try await client.datastores().isEmpty)
            #expect(try await client.groups(in: "backup-main").isEmpty)
            #expect(try await client.tasks().isEmpty)
            // An empty datastore list sends no per-store request.
            #expect(await fake.receivedSpecs.count == 3)
        }
    }

    @Test func nullDataOnStatusThrowsInvalidResponse() async {
        let fake = FakeHTTPClient.json(#"{"data":null}"#)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).datastoreStatus("backup-main")
        }
    }
}

// MARK: - Partial failures

@Suite("PBSClient per-store failures")
struct PBSClientPartialFailureTests {
    @Test func refusedStatusKeepsDatastoreWithoutSpaceButWithGroups() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(#"{"data":[{"store":"backup-main","comment":"Primary ZFS pool"}]}"#),
            .failure(HTTPClientError.forbidden),
            PBSFixtures.response(PBSFixtures.mainGroups),
        ])
        let stores = try await makeClient(fake).datastores()
        let store = try #require(stores.first)
        #expect(stores.count == 1)
        #expect(store.name == "backup-main")
        #expect(store.comment == "Primary ZFS pool")
        #expect(store.total == nil)
        #expect(store.used == nil)
        #expect(store.available == nil)
        #expect(store.usage == nil)
        #expect(store.groups.count == 3)
        // No retry after the 403.
        #expect(await fake.receivedSpecs.count == 3)
    }

    @Test func refusedGroupsKeepsDatastoreWithSpaceButNoGroups() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(#"{"data":[{"store":"backup-main"}]}"#),
            PBSFixtures.response(PBSFixtures.mainStatus),
            .failure(HTTPClientError.forbidden),
        ])
        let store = try #require(try await makeClient(fake).datastores().first)
        #expect(store.total == 1_000_000_000_000)
        #expect(store.groups.isEmpty)
        #expect(await fake.receivedSpecs.count == 3)
    }

    /// A token revoked mid-refresh stops at the first 401: no burst of refused requests.
    @Test func unauthorizedOnStoreDetailsStopsTheRefresh() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(PBSFixtures.datastoreList),
            .failure(HTTPClientError.unauthorized),
            PBSFixtures.response(PBSFixtures.mainGroups),
        ])
        await #expect(throws: ServiceProviderError.unauthorized) {
            _ = try await makeClient(fake).datastores()
        }
        #expect(await fake.receivedSpecs.count == 2)
    }

    @Test func statusAndGroupsFailuresOnOneStoreDoNotAffectTheNext() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(PBSFixtures.datastoreList),
            .failure(HTTPClientError.unreachable),
            PBSFixtures.response("<html>oops</html>"),
            PBSFixtures.response(PBSFixtures.offsiteStatus),
            PBSFixtures.response(PBSFixtures.offsiteGroups),
        ])
        let stores = try await makeClient(fake).datastores()
        #expect(stores.map(\.name) == ["backup-main", "offsite"])
        #expect(stores[0].total == nil)
        #expect(stores[0].groups.isEmpty)
        #expect(stores[1].total == 2_000_000_000_000)
        #expect(stores[1].groups.count == 2)
    }

    @Test func nullStatusDataKeepsDatastoreWithoutSpace() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(#"{"data":[{"store":"backup-main"}]}"#),
            PBSFixtures.response(#"{"data":null}"#),
            PBSFixtures.response(#"{"data":null}"#),
        ])
        let store = try #require(try await makeClient(fake).datastores().first)
        #expect(store.total == nil)
        #expect(store.groups.isEmpty)
    }

    @Test func cancellationDuringStatusIsRethrown() async {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(PBSFixtures.datastoreList),
            .failure(CancellationError()),
            PBSFixtures.response(PBSFixtures.mainGroups),
        ])
        await #expect(throws: CancellationError.self) {
            _ = try await makeClient(fake).datastores()
        }
        // Stopped right away: no groups request, no second store.
        #expect(await fake.receivedSpecs.count == 2)
    }

    @Test func cancellationDuringGroupsIsRethrown() async {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(PBSFixtures.datastoreList),
            PBSFixtures.response(PBSFixtures.mainStatus),
            .failure(CancellationError()),
            PBSFixtures.response(PBSFixtures.offsiteStatus),
        ])
        await #expect(throws: CancellationError.self) {
            _ = try await makeClient(fake).datastores()
        }
        #expect(await fake.receivedSpecs.count == 3)
    }

    @Test func cancellationOnListIsRethrown() async {
        let fake = FakeHTTPClient(.failure(CancellationError()))
        await #expect(throws: CancellationError.self) {
            try await makeClient(fake).checkConnection()
        }
    }
}

// MARK: - Datastore name validation

@Suite("PBSClient datastore name validation")
struct PBSClientStoreNameTests {
    @Test(arguments: ["backup-main", "offsite_2", "store.v2", "B4ckup"])
    func safeNamesAreAccepted(name: String) throws {
        #expect(try PBSClient.storeSegment(name) == name)
    }

    @Test(arguments: ["", ".", "..", "../admin", "a/b", "store?x=1", "store%2F", "store#frag", "störe", "store name", "store\u{0}"])
    func unsafeNamesAreRejected(name: String) {
        #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try PBSClient.storeSegment(name)
        }
    }

    @Test func groupsWithUnsafeNameSendsNoRequest() async {
        let fake = FakeHTTPClient.json(PBSFixtures.mainGroups)
        await #expect(throws: ServiceProviderError.invalidResponse) {
            _ = try await makeClient(fake).groups(in: "../../nodes/localhost")
        }
        #expect(await fake.receivedSpecs.isEmpty)
    }

    @Test func unsafeNameFromServerIsKeptWithoutDetailsAndNeverRequested() async throws {
        let fake = FakeHTTPClient(sequence: [
            PBSFixtures.response(#"{"data":[{"store":"../../access/users"},{"store":"offsite"}]}"#),
            PBSFixtures.response(PBSFixtures.offsiteStatus),
            PBSFixtures.response(PBSFixtures.offsiteGroups),
        ])
        let stores = try await makeClient(fake).datastores()
        #expect(stores.map(\.name) == ["../../access/users", "offsite"])
        #expect(stores[0].total == nil)
        #expect(stores[0].groups.isEmpty)
        let requested = await paths(fake)
        #expect(requested == [
            "/api2/json/admin/datastore",
            "/api2/json/admin/datastore/offsite/status",
            "/api2/json/admin/datastore/offsite/groups",
        ])
        #expect(!requested.contains { $0.contains("..") || $0.contains("access") })
    }
}

// MARK: - Model helpers

@Suite("PBSDatastore usage")
struct PBSDatastoreUsageTests {
    @Test func usageIsUsedOverTotal() {
        #expect(PBSDatastore(name: "s", total: 200, used: 50).usage == 0.25)
    }

    @Test func usageIsNilWhenUnknownOrZeroTotal() {
        #expect(PBSDatastore(name: "s").usage == nil)
        #expect(PBSDatastore(name: "s", total: 100).usage == nil)
        #expect(PBSDatastore(name: "s", total: 0, used: 10).usage == nil)
    }

    @Test func usageIsClampedBetweenZeroAndOne() {
        #expect(PBSDatastore(name: "s", total: 100, used: 150).usage == 1)
        #expect(PBSDatastore(name: "s", total: 100, used: -5).usage == 0)
    }
}
