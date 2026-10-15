import Foundation

/// What VoiceOver reads for a chart: per series, the latest and highest values
/// ("node-a: latest 23 %, highest 41 %"). At most 4 series.
func chartSummary(_ series: [(name: String, values: [Double])], format: (Double) -> String) -> String {
    let parts = series.prefix(4).compactMap { item -> String? in
        let finite = item.values.filter(\.isFinite)
        guard let latest = finite.last, let highest = finite.max() else { return nil }
        let values = String(localized: "latest \(format(latest)), highest \(format(highest))")
        return item.name.isEmpty ? values : "\(item.name): \(values)"
    }
    return parts.isEmpty ? String(localized: "No data for this period.") : parts.joined(separator: "; ")
}
