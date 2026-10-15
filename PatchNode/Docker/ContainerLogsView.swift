import SwiftUI
import DockerKit
import PatchNodeCore
import ProxmoxKit

enum LogStreamFilter: Hashable, CaseIterable {
    case all, stdout, stderr

    var title: LocalizedStringKey {
        switch self {
        case .all: "All output"
        case .stdout: "stdout"
        case .stderr: "stderr"
        }
    }

    func matches(_ stream: DockerLogLine.Stream) -> Bool {
        switch self {
        case .all: true
        case .stdout: stream != .stderr
        case .stderr: stream == .stderr
        }
    }
}

/// Last lines of a container's logs; no continuous streaming in this phase.
struct ContainerLogsView: View {
    let item: DockerInventory.ContainerItem

    static let pageSize = DockerClient.defaultLogTail

    @Environment(DockerStore.self) private var store
    @State private var lines: [DockerLogLine] = []
    /// Lines requested; changing it reloads through `.task(id:)`, which SwiftUI
    /// cancels when the screen goes away.
    @State private var requestedTail = ContainerLogsView.pageSize
    /// Lines actually asked for in the last successful load.
    @State private var loadedTail = 0
    @State private var loadState: ServiceLoadState = .loading
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var streamFilter: LogStreamFilter = .all

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let message = loadState.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if canLoadMore {
                    Button {
                        requestedTail = min(requestedTail + Self.pageSize, DockerClient.maxLogTail)
                    } label: {
                        Label("Load \(Self.pageSize) earlier lines", systemImage: "arrow.up.circle")
                    }
                    .disabled(isLoading)
                }
                let visible = visibleLines
                if visible.isEmpty && loadState == .loaded {
                    Text(lines.isEmpty ? LocalizedStringKey("No logs.") : LocalizedStringKey("No line matches."))
                        .foregroundStyle(.secondary)
                }
                ForEach(visible) { line in
                    LogLineRow(line: line)
                        .id(line.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                }
            }
            .readableWidth(ReadableWidth.data, grouped: false)
            .listStyle(.plain)
            .overlay {
                if isLoading && lines.isEmpty { ProgressView() }
            }
            .onChange(of: lines.last?.id) {
                // Newest lines are at the bottom, like a terminal.
                if let last = visibleLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text("Search the logs"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Output", selection: $streamFilter) {
                    ForEach(LogStreamFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
        .task(id: requestedTail) { await load() }
        .refreshable { await load() }
    }

    /// Docker returned exactly what was asked: there may be older lines.
    private var canLoadMore: Bool {
        lines.count >= loadedTail && loadedTail == requestedTail && loadedTail < DockerClient.maxLogTail
    }

    private var visibleLines: [DockerLogLine] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return lines.filter { line in
            streamFilter.matches(line.stream) && (query.isEmpty || line.text.localizedStandardContains(query))
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let client = await store.client(for: item.serviceID) else {
            loadState = .unauthorized
            return
        }
        let tail = requestedTail
        do {
            lines = try await client.logs(on: item.host, containerID: item.container.id, tail: tail)
            loadedTail = tail
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadState = ServiceLoadState(error: error)
            store.reportRejectedToken(for: item.serviceID, state: loadState)
        }
    }
}

struct LogLineRow: View {
    let line: DockerLogLine

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                if line.stream == .stderr {
                    Text(verbatim: "stderr")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
                if let timestamp = line.timestamp {
                    Text(timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .font(.caption.monospaced())
                .foregroundStyle(line.stream == .stderr ? Color.red : Color.primary)
                .textSelection(.enabled)
        }
    }
}
