/// Largest-Triangle-Three-Buckets downsampling: keeps the visual shape of a series
/// (peaks included) while capping the number of points handed to Swift Charts.
/// Returns `items` unchanged when it already has `threshold` points or fewer.
/// `items` must be sorted by `x`.
public func downsampleLTTB<T>(
    _ items: [T],
    threshold: Int,
    x: (T) -> Double,
    y: (T) -> Double
) -> [T] {
    guard threshold >= 3, items.count > threshold else { return items }

    var sampled: [T] = []
    sampled.reserveCapacity(threshold)
    sampled.append(items[0])

    let bucketSize = Double(items.count - 2) / Double(threshold - 2)
    var previousIndex = 0

    for bucket in 0..<(threshold - 2) {
        let start = Int(Double(bucket) * bucketSize) + 1
        let end = min(Int(Double(bucket + 1) * bucketSize) + 1, items.count - 1)

        // Average of the next bucket (or the last point for the final bucket).
        let nextStart = end
        let nextEnd = min(Int(Double(bucket + 2) * bucketSize) + 1, items.count)
        var averageX = 0.0
        var averageY = 0.0
        let nextCount = max(nextEnd - nextStart, 1)
        for index in nextStart..<max(nextEnd, nextStart + 1) where index < items.count {
            averageX += x(items[index])
            averageY += y(items[index])
        }
        averageX /= Double(nextCount)
        averageY /= Double(nextCount)

        let previousX = x(items[previousIndex])
        let previousY = y(items[previousIndex])
        var bestArea = -1.0
        var bestIndex = start
        for index in start..<max(end, start + 1) where index < items.count - 1 {
            let area = abs(
                (previousX - averageX) * (y(items[index]) - previousY)
                    - (previousX - x(items[index])) * (averageY - previousY)
            )
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        sampled.append(items[bestIndex])
        previousIndex = bestIndex
    }

    sampled.append(items[items.count - 1])
    return sampled
}
