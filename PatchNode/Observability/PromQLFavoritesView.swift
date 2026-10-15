import SwiftUI
import SwiftData
import Charts
import TipKit
import PatchNodeCore
import ObservabilityKit

enum PromQLRange: Int, CaseIterable, Identifiable {
    case hour = 60
    case sixHours = 360
    case day = 1440
    case week = 10080

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .hour: "1 hour"
        case .sixHours: "6 hours"
        case .day: "24 hours"
        case .week: "7 days"
        }
    }
}

extension PromQLUnit {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Number"
        case .percent: "Percent (0–100)"
        case .bytes: "Bytes"
        case .bytesPerSecond: "Bytes per second"
        case .seconds: "Seconds"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .none: value.formatted(.number.precision(.significantDigits(1...4)))
        case .percent: (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
        case .bytes: Format.bytes(value)
        case .bytesPerSecond: Format.rate(value)
        case .seconds: Format.duration(value)
        }
    }
}

struct PromQLFavoritesView: View {
    @Query(sort: \PromQLFavorite.createdAt) private var allFavorites: [PromQLFavorite]
    @Environment(\.modelContext) private var modelContext
    @Environment(ObservabilityStore.self) private var store
    @State private var isAdding = false
    @State private var favoriteToDelete: PromQLFavorite?
    @State private var charts: [UUID: FavoriteChartState] = [:]

    /// Charts of the Prometheus services shown (the demo's, or the user's).
    private var favorites: [PromQLFavorite] {
        let ids = Set(store.services.map(\.id))
        // One per ID: an iCloud sync can store a chart twice.
        return allFavorites.uniqued(by: \.id).filter { ids.contains($0.serviceID) }
    }

    var body: some View {
        List {
            if favorites.isEmpty {
                ContentUnavailableView {
                    Label("No PromQL charts yet.", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Add a query, for example CPU, memory or disk usage from node_exporter.")
                }
            }
            ForEach(favorites) { favorite in
                FavoriteChartView(favorite: favorite, serviceName: serviceName(for: favorite), state: charts[favorite.id] ?? .loading)
                    .swipeActions {
                        Button("Delete", systemImage: "trash") { favoriteToDelete = favorite }
                            .tint(.red)
                    }
            }
        }
        .readableWidth(ReadableWidth.data)
        .navigationTitle("PromQL charts")
        // One query at a time, stopping at the first refused credential: ten
        // favorites must not become ten simultaneous 401s (CrowdSec / fail2ban).
        .task(id: favorites.map(\.id)) { await loadAll() }
        .refreshable { await loadAll() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add a chart", systemImage: "plus") {
                    PromQLChartTip().invalidate(reason: .actionPerformed)
                    isAdding = true
                }
                .popoverTip(PromQLChartTip())
                    .disabled(store.prometheusServices.isEmpty)
            }
        }
        .sheet(isPresented: $isAdding) {
            PromQLFavoriteEditor()
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { favoriteToDelete != nil }, set: { if !$0 { favoriteToDelete = nil } }),
            titleVisibility: .visible,
            presenting: favoriteToDelete
        ) { favorite in
            Button("Delete \(favorite.name)", role: .destructive) {
                favoriteToDelete = nil
                try? modelContext.deleteFavorite(id: favorite.id)
                try? modelContext.save()
            }
        }
    }

    private var deleteTitle: String {
        guard let favoriteToDelete else { return "" }
        return String(localized: "Delete “\(favoriteToDelete.name)”?")
    }

    private func serviceName(for favorite: PromQLFavorite) -> String? {
        store.services.first { $0.id == favorite.serviceID }?.name
    }

    private func loadAll() async {
        // Read the models up front: one may be deleted while a query runs.
        let jobs = favorites.map { (id: $0.id, serviceID: $0.serviceID, query: $0.query, minutes: $0.rangeMinutes) }
        var refused = Set<UUID>()
        for job in jobs {
            guard !Task.isCancelled else { return }
            guard !refused.contains(job.serviceID), let client = await store.prometheusClient(for: job.serviceID) else {
                charts[job.id] = .failed(String(localized: "The Prometheus service can't be queried right now."))
                continue
            }
            if charts[job.id] == nil { charts[job.id] = .loading }
            let end = Date.now
            let start = end.addingTimeInterval(-Double(job.minutes) * 60)
            do {
                let result = try await client.queryRange(job.query, start: start, end: end)
                charts[job.id] = .loaded(Array(result.series.prefix(FavoriteChartView.maxSeries)))
            } catch is CancellationError {
                return
            } catch PrometheusQueryError.rejected(let message) {
                charts[job.id] = .failed(message)
            } catch {
                let state = ServiceLoadState(error: error)
                charts[job.id] = .failed(state.message ?? String(localized: "The query failed."))
                if state == .unauthorized || state == .forbidden {
                    refused.insert(job.serviceID)
                    store.reportRejectedToken(for: job.serviceID, state: state)
                }
            }
        }
    }
}

enum FavoriteChartState {
    case loading
    case loaded([PrometheusSeries])
    case failed(String)
}

/// Display only: the list loads every chart sequentially.
struct FavoriteChartView: View {
    let favorite: PromQLFavorite
    let serviceName: String?
    let state: FavoriteChartState

    /// Legends beyond this are unreadable on a phone.
    static let maxSeries = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: favorite.name).font(.headline)
                Spacer()
                if case .loading = state { ProgressView() }
            }
            if let serviceName {
                Text(verbatim: serviceName).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Its Prometheus service was removed.").font(.caption).foregroundStyle(.red)
            }
            switch state {
            case .loading:
                EmptyView()
            case .failed(let message):
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.red)
            case .loaded(let series):
                if series.isEmpty {
                    Text("No data for this period.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    PromQLChart(series: series, unit: favorite.unit)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PromQLChart: View {
    let series: [PrometheusSeries]
    let unit: PromQLUnit
    /// Built once per chart, not on every body evaluation.
    private let points: [Point]

    init(series: [PrometheusSeries], unit: PromQLUnit) {
        self.series = series
        self.unit = unit
        var points: [Point] = []
        for (seriesIndex, item) in series.enumerated() {
            let label = item.label
            for sample in item.samples {
                points.append(Point(id: points.count, seriesIndex: seriesIndex, series: label, time: sample.time, value: sample.value))
            }
        }
        self.points = points
    }

    private nonisolated struct Point: Identifiable {
        let id: Int
        let seriesIndex: Int
        let series: String
        let time: Date
        let value: Double
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Value", point.value)
            )
            .foregroundStyle(by: .value("Series", point.series))
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(unit.format(number))
                    }
                }
            }
        }
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .frame(height: 180)
        // One element for VoiceOver instead of one per point.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Chart"))
        .accessibilityValue(Text(chartSummary(series.map { ($0.label, $0.samples.map(\.value)) }, format: unit.format)))
    }

}

/// Add a PromQL chart; saving requires a successful test of the current inputs.
struct PromQLFavoriteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ObservabilityStore.self) private var store

    @State private var name = ""
    @State private var query = ""
    @State private var unit: PromQLUnit = .percent
    @State private var range: PromQLRange = .hour
    @State private var serviceID: UUID?
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var isTesting = false
    @State private var preview: [PrometheusSeries] = []
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("PromQL query", text: $query, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(2...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Picker("Unit", selection: $unit) {
                        ForEach(PromQLUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Range", selection: $range) {
                        ForEach(PromQLRange.allCases) { Text($0.title).tag($0) }
                    }
                    if store.prometheusServices.count > 1 {
                        Picker("Prometheus", selection: $serviceID) {
                            ForEach(store.prometheusServices) { Text(verbatim: $0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }
                Section("Examples (node_exporter)") {
                    ForEach(PromQLExample.all) { example in
                        Button {
                            name = Self.exampleName(example.id)
                            query = example.query
                            unit = example.unit
                        } label: {
                            Text(verbatim: Self.exampleName(example.id))
                        }
                    }
                }
                Section {
                    Button("Test query") {
                        testTask?.cancel()
                        testTask = Task { await test() }
                    }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting || serviceID == nil)
                    if isTesting { ProgressView() }
                    if let testMessage {
                        Label(testMessage, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSucceeded ? Color.green : Color.red)
                    }
                    if testSucceeded && !preview.isEmpty {
                        PromQLChart(series: preview, unit: unit)
                    }
                } footer: {
                    Text("The chart can only be saved after a successful test.")
                }
            }
            .navigationTitle("Add a chart")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!testSucceeded || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if serviceID == nil { serviceID = store.prometheusServices.first?.id }
            }
            .onDisappear { testTask?.cancel() }
            // Any edit invalidates the previous test.
            .onChange(of: query) { invalidateTest() }
            .onChange(of: range) { invalidateTest() }
            .onChange(of: serviceID) { invalidateTest() }
            .privacyCover()
        }
    }

    static func exampleName(_ id: String) -> String {
        switch id {
        case "cpu": String(localized: "CPU usage")
        case "memory": String(localized: "Memory usage")
        case "disk": String(localized: "Root disk usage")
        default: id
        }
    }

    private func invalidateTest() {
        testTask?.cancel()
        isTesting = false
        testSucceeded = false
        testMessage = nil
        preview = []
    }

    private func test() async {
        // Set before the first await so a second tap can't start a parallel test.
        isTesting = true
        defer { isTesting = false }
        let testedQuery = query
        let testedRange = range
        guard let serviceID, let client = await store.prometheusClient(for: serviceID) else {
            testMessage = String(localized: "The Prometheus service can't be queried right now.")
            return
        }
        /// The inputs haven't changed since the test started.
        func stillCurrent() -> Bool {
            !Task.isCancelled && testedQuery == query && testedRange == range && serviceID == self.serviceID
        }
        let end = Date.now
        let start = end.addingTimeInterval(-Double(range.rawValue) * 60)
        do {
            let result = try await client.queryRange(query, start: start, end: end)
            // Inputs edited while the query ran: this result is for other inputs.
            guard stillCurrent() else { return }
            preview = Array(result.series.prefix(FavoriteChartView.maxSeries))
            testSucceeded = true
            let count = result.series.count
            testMessage = String(localized: "Query OK: \(count) series.")
        } catch PrometheusQueryError.rejected(let message) {
            guard stillCurrent() else { return }
            testSucceeded = false
            testMessage = message
        } catch {
            let state = ServiceLoadState(error: error)
            if state == .unauthorized || state == .forbidden {
                store.reportRejectedToken(for: serviceID, state: state)
            }
            guard stillCurrent() else { return }
            testSucceeded = false
            testMessage = ServiceLoadState(error: error).message ?? String(localized: "The query failed.")
        }
    }

    private func save() {
        guard testSucceeded, let serviceID else { return }
        let favorite = PromQLFavorite(
            name: name.trimmingCharacters(in: .whitespaces),
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            unit: unit,
            rangeMinutes: range.rawValue,
            serviceID: serviceID
        )
        modelContext.insert(favorite)
        try? modelContext.save()
        dismiss()
    }
}
