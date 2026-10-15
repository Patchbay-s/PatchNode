import Foundation
import Testing
@testable import PatchNodeCore

private struct Sample: Equatable {
    let x: Double
    let y: Double
}

private func downsample(_ items: [Sample], threshold: Int) -> [Sample] {
    downsampleLTTB(items, threshold: threshold, x: \.x, y: \.y)
}

private func wave(count: Int) -> [Sample] {
    (0..<count).map { Sample(x: Double($0) * 60, y: 50 + 40 * sin(Double($0) / 100)) }
}

@Suite("downsampleLTTB")
struct DownsamplingTests {
    @Test(arguments: [0, 1, 2, 499, 500])
    func inputAtOrBelowThresholdIsReturnedUnchanged(count: Int) {
        let input = wave(count: count)
        #expect(downsample(input, threshold: 500) == input)
    }

    @Test func tenThousandPointsAreReducedToExactlyThreshold() {
        #expect(downsample(wave(count: 10_000), threshold: 500).count == 500)
    }

    @Test(arguments: [3, 4, 50, 501, 9_999])
    func outputCountEqualsThresholdForAnyThresholdBelowCount(threshold: Int) {
        #expect(downsample(wave(count: 10_000), threshold: threshold).count == threshold)
    }

    @Test func firstAndLastPointsArePreserved() {
        let input = wave(count: 10_000)
        let output = downsample(input, threshold: 500)
        #expect(output.first == input.first)
        #expect(output.last == input.last)
    }

    @Test func outputXIsStrictlyIncreasing() {
        let output = downsample(wave(count: 10_000), threshold: 500)
        for (previous, next) in zip(output, output.dropFirst()) {
            #expect(previous.x < next.x)
        }
    }

    @Test func outputContainsOnlyInputPoints() {
        let input = wave(count: 2_000)
        let inputXs = Set(input.map(\.x))
        #expect(downsample(input, threshold: 100).allSatisfy { inputXs.contains($0.x) })
    }

    @Test func singleSpikeInFlatSeriesIsKept() {
        var input = (0..<10_000).map { Sample(x: Double($0), y: 1) }
        input[6_543] = Sample(x: 6_543, y: 1_000_000)
        let output = downsample(input, threshold: 500)
        #expect(output.contains(Sample(x: 6_543, y: 1_000_000)))
        #expect(output.map(\.y).max() == 1_000_000)
    }

    @Test(arguments: [-1, 0, 1, 2])
    func thresholdBelowThreeReturnsInput(threshold: Int) {
        let input = wave(count: 1_000)
        #expect(downsample(input, threshold: threshold) == input)
    }
}
