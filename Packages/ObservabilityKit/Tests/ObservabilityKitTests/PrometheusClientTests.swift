import Foundation
import Testing
import PatchNodeCore
@testable import ObservabilityKit

@Suite("PrometheusClient")
struct PrometheusClientTests {
    private func client(_ fake: FakeHTTPClient, base: URL = Fixtures.prometheusURL, credential: String = "") -> PrometheusClient {
        PrometheusClient(baseURL: base, credential: credential, httpClient: fake)
    }

    // MARK: URLs

    @Test func queryWithoutTimeSendsOnlyQueryItem() async throws {
        let fake = FakeHTTPClient.json(Fixtures.vector)
        _ = try await client(fake).query(#"up{job="node"}"#)
        let url = try #require(await fake.receivedURLs.first)
        #expect(url.host == "prometheus.example.invalid")
        #expect(url.path == "/api/v1/query")
        #expect(queryItems(url) == ["query": #"up{job="node"}"#])
        #expect(await fake.receivedSpecs.first?.method == .get)
    }

    @Test func queryWithTimeFormatsEpochWithThreeDecimals() async throws {
        let fake = FakeHTTPClient.json(Fixtures.vector)
        _ = try await client(fake).query("up", at: date(referenceEpoch + 0.12345))
        let url = try #require(await fake.receivedURLs.first)
        #expect(queryItems(url) == ["query": "up", "time": "1714557600.123"])
    }

    /// "+" must reach Prometheus as "+", not as a space (form decoding).
    @Test func plusInQueryIsPercentEncoded() async throws {
        let fake = FakeHTTPClient.json(Fixtures.vector)
        _ = try await client(fake).query("node_load1 + node_load5")
        let url = try #require(await fake.receivedURLs.first)
        #expect(url.absoluteString.contains("%2B"))
        #expect(!(url.query(percentEncoded: true) ?? "").contains("+"))
        #expect(queryItems(url)["query"] == "node_load1 + node_load5")
    }

    @Test func queryKeepsBaseSubPath() async throws {
        let fake = FakeHTTPClient.json(Fixtures.vector)
        _ = try await client(fake, base: URL(string: "https://lab.example.invalid/prometheus")!).query("up")
        #expect(await fake.receivedPaths == ["/prometheus/api/v1/query"])
    }

    @Test func queryRangeSendsStartEndAndDefaultStepCappedAt500Points() async throws {
        let fake = FakeHTTPClient.json(Fixtures.matrix)
        _ = try await client(fake).queryRange("rate(node_cpu_seconds_total[5m])", start: date(referenceEpoch), end: date(referenceEpoch + 3600))
        let url = try #require(await fake.receivedURLs.first)
        #expect(url.path == "/api/v1/query_range")
        #expect(queryItems(url) == [
            "query": "rate(node_cpu_seconds_total[5m])",
            "start": "1714557600.000",
            "end": "1714561200.000",
            "step": "8.000", // ceil(3600 / 500)
        ])
    }

    @Test(arguments: [
        // (span, requested step, expected step)
        (3600.0, Optional(15.0), "15.000"),   // coarse enough: kept
        (3600.0, Optional(2.0), "8.000"),     // too fine: clamped to 500 points
        (86_400.0, nil as Double?, "173.000"),// ceil(172.8)
        (60.0, Optional(0.5), "1.000"),       // never below 1 s
        (0.0, nil as Double?, "1.000"),       // empty span
        (-100.0, nil as Double?, "1.000"),    // reversed range
    ])
    func queryRangeClampsStep(span: Double, step: Double?, expected: String) async throws {
        let fake = FakeHTTPClient.json(Fixtures.matrix)
        _ = try await client(fake).queryRange("up", start: date(referenceEpoch), end: date(referenceEpoch + span), step: step)
        let url = try #require(await fake.receivedURLs.first)
        let items = queryItems(url)
        #expect(items["step"] == expected)
        if let stepValue = Double(expected), span > 0 {
            #expect(span / stepValue <= Double(PrometheusClient.maxPoints))
        }
    }

    @Test func targetsRequestsActiveState() async throws {
        let fake = FakeHTTPClient.json(Fixtures.emptyTargets)
        _ = try await client(fake).targets()
        let url = try #require(await fake.receivedURLs.first)
        #expect(url.path == "/api/v1/targets")
        #expect(queryItems(url) == ["state": "active"])
    }

    @Test func checkConnectionUsesBuildinfo() async throws {
        let fake = FakeHTTPClient.json(Fixtures.buildinfo)
        try await client(fake).checkConnection()
        #expect(await fake.receivedPaths == ["/api/v1/status/buildinfo"])
    }

    // MARK: Auth header

    @Test func basicHeaderSentWhenCredentialPresent() async throws {
        let fake = FakeHTTPClient.json(Fixtures.vector)
        _ = try await client(fake, credential: Fixtures.basicCredential).query("up")
        let spec = try #require(await fake.receivedSpecs.first)
        let expected = "Basic " + Data(Fixtures.basicCredential.utf8).base64EncodedString()
        #expect(spec.headers == ["Authorization": expected])
        // Masked in the log-safe description.
        #expect(!spec.redactedDescription.contains(Data(Fixtures.basicCredential.utf8).base64EncodedString()))
        #expect(!spec.redactedDescription.contains("fake-password-1234"))
    }

    @Test func noHeaderWhenCredentialEmpty() async throws {
        let fake = FakeHTTPClient.json(Fixtures.vector)
        _ = try await client(fake).query("up")
        #expect(await fake.receivedSpecs.first?.headers.isEmpty == true)
    }

    // MARK: Decoding

    @Test func decodesVectorAndKeepsNaNSeriesWithoutSample() async throws {
        let result = try await client(.json(Fixtures.vector)).query("up")
        guard case .vector(let series) = result else { Issue.record("expected vector, got \(result)"); return }
        #expect(series.count == 3)
        #expect(series[0].metric["instance"] == "node.example.invalid:9100")
        #expect(series[0].samples.count == 1)
        #expect(series[0].samples[0].value == 1)
        #expect(abs(series[0].samples[0].time.timeIntervalSince1970 - 1_714_557_600.123) < 0.0005)
        #expect(series[1].samples.map(\.value) == [0.5])
        #expect(series[2].samples.isEmpty) // "NaN" dropped
        #expect(result.series == series)
    }

    @Test func decodesMatrixDroppingNonFiniteValuesAndMalformedSeries() async throws {
        let result = try await client(.json(Fixtures.matrix)).queryRange("up", start: date(referenceEpoch), end: date(referenceEpoch + 60))
        guard case .matrix(let series) = result else { Issue.record("expected matrix, got \(result)"); return }
        #expect(series.count == 2) // "garbage-series" skipped
        #expect(series[0].samples.map(\.value) == [0.5, 0.75]) // NaN, +Inf, -Inf dropped
        #expect(series[0].samples.map(\.time) == [date(referenceEpoch), date(referenceEpoch + 60)])
        // Timestamp given as a string is accepted too.
        #expect(series[1].samples.map(\.value) == [12, 13.5])
        #expect(series[1].samples.last?.time == date(referenceEpoch + 15))
    }

    @Test func decodesScalarAsOneUnlabeledSeries() async throws {
        let result = try await client(.json(Fixtures.scalar)).query("scalar(sum(up))")
        #expect(result == .scalar(.init(time: date(referenceEpoch + 0.5), value: 42.5)))
        #expect(result.series.count == 1)
        #expect(result.series.first?.metric == [:])
        #expect(result.series.first?.label == "value")
    }

    @Test func nonFiniteScalarHasNoSeries() async throws {
        let result = try await client(.json(Fixtures.scalarNaN)).query("0/0")
        #expect(result == .scalar(nil))
        #expect(result.series.isEmpty)
    }

    @Test func decodesStringResult() async throws {
        let result = try await client(.json(Fixtures.stringResult)).query(#""hello PatchNode""#)
        #expect(result == .string("hello PatchNode"))
        #expect(result.series.isEmpty)
    }

    @Test func emptyVectorIsEmpty() async throws {
        let result = try await client(.json(Fixtures.emptyVector)).query("absent_metric")
        #expect(result == .vector([]))
    }

    @Test(arguments: [
        (["instance": "node.example.invalid:9100", "job": "node", "__name__": "up"], "node.example.invalid:9100"),
        (["job": "node", "__name__": "up"], "node"),
        (["__name__": "up"], "up"),
        (["mode": "idle", "cpu": "0"], "cpu=0,mode=idle"),
        ([:], "value"),
    ])
    func seriesLabelPrefersInstanceThenJobThenName(metric: [String: String], expected: String) {
        #expect(PrometheusSeries(metric: metric, samples: []).label == expected)
    }

    // MARK: Errors

    @Test(arguments: [400, 422])
    func badQueryIsRejectedWithPrometheusMessage(status: Int) async throws {
        let fake = FakeHTTPClient.json(Fixtures.badData, status: status)
        await #expect(throws: PrometheusQueryError.rejected(#"invalid parameter "query": 1:4: parse error: unexpected "}" in label matching, expected string"#)) {
            _ = try await client(fake).query("up{")
        }
        #expect(await fake.receivedSpecs.count == 1)
    }

    @Test func rejectedMessageIsCappedAt500Characters() async throws {
        let long = String(repeating: "x", count: 800)
        let fake = FakeHTTPClient.json(Fixtures.badData(message: long), status: 400)
        do {
            _ = try await client(fake).queryRange("up{", start: date(referenceEpoch), end: date(referenceEpoch + 60))
            Issue.record("expected rejection")
        } catch PrometheusQueryError.rejected(let message) {
            #expect(message.count == 500)
        }
    }

    @Test func badRequestWithoutJSONIsUnexpectedStatus() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(400)) {
            _ = try await client(.json("Bad Request", status: 400)).query("up")
        }
    }

    @Test func errorJSONOnOtherStatusIsUnexpectedStatus() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(503)) {
            _ = try await client(.json(Fixtures.badData, status: 503)).query("up")
        }
    }

    @Test func serverErrorIsUnexpectedStatus() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await client(FakeHTTPClient(.serverError)).query("up")
        }
    }

    @Test func statusErrorOn200IsDecodingFailure() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(.json(Fixtures.statusErrorOn200)).query("up")
        }
    }

    @Test func missingDataOn200IsDecodingFailure() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(.json(Fixtures.missingData)).query("up")
        }
    }

    @Test func unknownResultTypeIsDecodingFailure() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(.json(#"{"status":"success","data":{"resultType":"histogram","result":[]}}"#)).query("up")
        }
    }

    @Test func invalidJSONIsDecodingFailure() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(FakeHTTPClient(.invalidJSON)).query("up")
        }
    }

    @Test func emptyBodyIsDecodingFailure() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(FakeHTTPClient(.emptyBody)).query("up")
        }
    }

    @Test(arguments: [
        (FakeHTTPClient.Outcome.unauthorized, ServiceProviderError.unauthorized),
        (.forbidden, .forbidden),
        (.timeout, .unreachable),
    ])
    func transportFailuresAreMappedWithoutRetry(outcome: FakeHTTPClient.Outcome, expected: ServiceProviderError) async throws {
        for operation in 0..<4 {
            let fake = FakeHTTPClient(outcome)
            let prometheus = client(fake, credential: Fixtures.basicCredential)
            await #expect(throws: expected) {
                switch operation {
                case 0: _ = try await prometheus.query("up")
                case 1: _ = try await prometheus.queryRange("up", start: date(referenceEpoch), end: date(referenceEpoch + 60))
                case 2: _ = try await prometheus.targets()
                default: try await prometheus.checkConnection()
                }
            }
            #expect(await fake.receivedSpecs.count == 1)
        }
    }

    @Test func nonHTTPSURLIsRefusedByRealClientWithoutNetwork() async throws {
        let prometheus = PrometheusClient(baseURL: URL(string: "http://prometheus.example.invalid")!)
        await #expect(throws: ServiceProviderError.unreachable) {
            _ = try await prometheus.query("up")
        }
    }

    // MARK: Targets

    @Test func decodesTargets() async throws {
        let targets = try await client(.json(Fixtures.targets)).targets()
        #expect(targets.count == 3) // the bare number is dropped
        let up = targets[0]
        #expect(up.job == "node")
        #expect(up.instance == "node.example.invalid:9100")
        #expect(up.scrapeURL == "http://node.example.invalid:9100/metrics")
        #expect(up.health == .up)
        #expect(up.lastError == nil) // "" → nil
        let scrape = try #require(up.lastScrape)
        #expect(abs(scrape.timeIntervalSince1970 - (referenceEpoch + 0.123456789)) < 0.000_01)

        let down = targets[1]
        #expect(down.health == .down)
        #expect(down.lastError?.contains("connection refused") == true)
        #expect(down.lastScrape == date(referenceEpoch - 2)) // 11:59:58+02:00 = 09:59:58Z

        #expect(targets[2].health == .unknown)
        #expect(targets[2].job == "blackbox")
    }

    @Test func unknownHealthValueIsUnknownAndMissingLabelsAreQuestionMarks() async throws {
        let targets = try await client(.json(#"{"status":"success","data":{"activeTargets":[{"health":"weird"}]}}"#)).targets()
        #expect(targets == [PrometheusTarget(job: "?", instance: "?", health: .unknown)])
    }

    @Test func emptyTargetsListIsEmpty() async throws {
        #expect(try await client(.json(Fixtures.emptyTargets)).targets().isEmpty)
        #expect(try await client(.json(#"{"status":"success","data":{}}"#)).targets().isEmpty)
    }

    @Test func targetsInvalidJSONOrEmptyBodyIsDecodingFailure() async throws {
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(FakeHTTPClient(.invalidJSON)).targets()
        }
        await #expect(throws: ServiceProviderError.decodingFailed) {
            _ = try await client(FakeHTTPClient(.emptyBody)).targets()
        }
    }

    @Test func targetsServerErrorIsUnexpectedStatus() async throws {
        await #expect(throws: ServiceProviderError.unexpectedStatus(500)) {
            _ = try await client(FakeHTTPClient(.serverError)).targets()
        }
    }
}
