import Foundation
import PatchNodeCore

/// One time series of a Prometheus result.
public struct PrometheusSeries: Sendable, Hashable, Identifiable {
    public struct Sample: Sendable, Hashable {
        public let time: Date
        public let value: Double

        public init(time: Date, value: Double) {
            self.time = time
            self.value = value
        }
    }

    public let metric: [String: String]
    /// One sample for an instant vector or scalar, many for a range (matrix).
    public let samples: [Sample]

    public init(metric: [String: String], samples: [Sample]) {
        self.metric = metric
        self.samples = samples
    }

    public var id: String {
        metric.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// Short legend: instance, job or the metric name, else every label.
    public var label: String {
        if let instance = metric["instance"] { return instance }
        if let job = metric["job"] { return job }
        if let name = metric["__name__"] { return name }
        return metric.isEmpty ? "value" : id
    }
}

/// `data` of `/api/v1/query` and `/api/v1/query_range`.
public enum PrometheusResult: Sendable, Hashable {
    case vector([PrometheusSeries])
    case matrix([PrometheusSeries])
    case scalar(PrometheusSeries.Sample?)
    case string(String)

    /// Every series, a scalar being one unlabeled series.
    public var series: [PrometheusSeries] {
        switch self {
        case .vector(let series), .matrix(let series): series
        case .scalar(let sample): sample.map { [PrometheusSeries(metric: [:], samples: [$0])] } ?? []
        case .string: []
        }
    }
}

extension PrometheusResult: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let type = try c.decode(String.self, forKey: AnyCodingKey("resultType"))
        switch type {
        case "vector":
            let items = try c.decode(LossyArray<RawSeries>.self, forKey: AnyCodingKey("result")).elements
            self = .vector(items.map { PrometheusSeries(metric: $0.metric, samples: $0.value.flatMap(\.sample).map { [$0] } ?? []) })
        case "matrix":
            let items = try c.decode(LossyArray<RawSeries>.self, forKey: AnyCodingKey("result")).elements
            self = .matrix(items.map { PrometheusSeries(metric: $0.metric, samples: ($0.values ?? []).compactMap(\.sample)) })
        case "scalar":
            self = .scalar((try? c.decode(RawSample.self, forKey: AnyCodingKey("result")))?.sample)
        case "string":
            let raw = try? c.decode(RawSample.self, forKey: AnyCodingKey("result"))
            self = .string(raw?.text ?? "")
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "resultType \(type)"))
        }
    }

    private struct RawSeries: Decodable {
        let metric: [String: String]
        let value: RawSample?
        let values: [RawSample]?

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            metric = (try? c.decodeIfPresent([String: String].self, forKey: AnyCodingKey("metric"))) ?? [:]
            value = try? c.decodeIfPresent(RawSample.self, forKey: AnyCodingKey("value"))
            values = (try? c.decodeIfPresent(LossyArray<RawSample>.self, forKey: AnyCodingKey("values")))?.elements
        }
    }

    /// `[<unix time>, "<value>"]` — the value is a string ("1.5", "NaN", "+Inf").
    private struct RawSample: Decodable {
        let time: Double
        let text: String

        init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            if let seconds = try? c.decode(Double.self) {
                time = seconds
            } else {
                time = Double(try c.decode(String.self)) ?? .nan
            }
            if let string = try? c.decode(String.self) {
                text = string
            } else {
                text = String(try c.decode(Double.self))
            }
        }

        /// Non-finite values (NaN, ±Inf) are dropped: they can't be charted.
        var sample: PrometheusSeries.Sample? {
            guard time.isFinite, let value = Double(text), value.isFinite else { return nil }
            return PrometheusSeries.Sample(time: Date(timeIntervalSince1970: time), value: value)
        }
    }
}

/// `/api/v1/targets` active target.
public struct PrometheusTarget: Sendable, Hashable, Identifiable, Decodable {
    public enum Health: String, Sendable, Hashable { case up, down, unknown }

    public let job: String
    public let instance: String
    public let scrapeURL: String?
    public let health: Health
    public let lastError: String?
    public let lastScrape: Date?

    public init(job: String, instance: String, scrapeURL: String? = nil, health: Health, lastError: String? = nil, lastScrape: Date? = nil) {
        self.job = job; self.instance = instance; self.scrapeURL = scrapeURL
        self.health = health; self.lastError = lastError; self.lastScrape = lastScrape
    }

    public var id: String { "\(job)|\(instance)|\(scrapeURL ?? "")" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        let labels = (try? c.decodeIfPresent([String: String].self, forKey: AnyCodingKey("labels"))) ?? [:]
        job = labels["job"] ?? "?"
        instance = labels["instance"] ?? "?"
        scrapeURL = c.lenientString(AnyCodingKey("scrapeUrl"))
        health = Health(rawValue: c.lenientString(AnyCodingKey("health")) ?? "") ?? .unknown
        let error = c.lenientString(AnyCodingKey("lastError"))
        lastError = (error?.isEmpty ?? true) ? nil : error
        lastScrape = c.lenientString(AnyCodingKey("lastScrape")).flatMap(RFC3339Timestamp.parse)
    }
}
