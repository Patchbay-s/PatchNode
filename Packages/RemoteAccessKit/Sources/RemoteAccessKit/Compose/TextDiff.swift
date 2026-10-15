import Foundation

/// The lines that change between two versions of a file, for the preview
/// before saving.
public enum TextDiff {
    public struct Line: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable { case unchanged, removed, added }
        public let id: Int
        public let kind: Kind
        public let text: String
        /// Line number in the old file (removed, unchanged) or the new one (added).
        public let number: Int
    }

    /// Every line, in reading order, removed lines before the added ones that
    /// replace them. `context`: unchanged lines kept around each change (nil:
    /// all).
    public static func lines(old: String, new: String, context: Int? = 3) -> [Line] {
        let before = split(old)
        let after = split(new)
        let difference = after.difference(from: before)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [(Line.Kind, String, Int)] = []
        var i = 0, j = 0
        while i < before.count || j < after.count {
            if i < before.count, removed.contains(i) {
                result.append((.removed, before[i], i + 1)); i += 1
            } else if j < after.count, inserted.contains(j) {
                result.append((.added, after[j], j + 1)); j += 1
            } else if i < before.count, j < after.count {
                result.append((.unchanged, before[i], i + 1)); i += 1; j += 1
            } else {
                break
            }
        }
        let kept: [(Line.Kind, String, Int)]
        if let context {
            // Distance to the nearest change, both ways, in two passes (O(n)).
            var distance = [Int](repeating: .max, count: result.count)
            var last = Int.min / 2
            for index in result.indices {
                if result[index].0 != .unchanged { last = index }
                distance[index] = index - last
            }
            last = Int.max / 2
            for index in result.indices.reversed() {
                if result[index].0 != .unchanged { last = index }
                distance[index] = min(distance[index], last - index)
            }
            kept = result.indices.filter { distance[$0] <= context }.map { result[$0] }
        } else {
            kept = result
        }
        return kept.enumerated().map { Line(id: $0.offset, kind: $0.element.0, text: $0.element.1, number: $0.element.2) }
    }

    public static func hasChanges(old: String, new: String) -> Bool {
        split(old) != split(new)
    }

    private static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

/// `.env` lines with their values hidden: `KEY=••••`, comments and blank
/// lines as they are.
public enum EnvMasking {
    public static func masked(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equal = line.firstIndex(of: "=") else { return String(line) }
            let value = line[line.index(after: equal)...]
            return String(line[...equal]) + (value.isEmpty ? "" : "••••")
        }.joined(separator: "\n")
    }
}
