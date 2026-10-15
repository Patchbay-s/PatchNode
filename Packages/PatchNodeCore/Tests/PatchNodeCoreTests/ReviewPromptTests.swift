import Foundation
import Testing
@testable import PatchNodeCore

struct ReviewPromptTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func usedOn(days: Int) -> ReviewPromptState {
        var state = ReviewPromptState()
        for day in 0..<days {
            state.recordUse(now: t0 + Double(day) * 86_400, calendar: calendar)
            state.recordUse(now: t0 + Double(day) * 86_400 + 60, calendar: calendar)
        }
        return state
    }

    private func moment(_ change: (inout ReviewPrompt.Moment) -> Void = { _ in }) -> ReviewPrompt.Moment {
        var moment = ReviewPrompt.Moment(appVersion: "1.1", serviceCount: 3, demoMode: false, sessionHadError: false,
                                         launchedAt: t0 - 3_600, lastEventAt: nil, now: t0)
        change(&moment)
        return moment
    }

    @Test func asksAfterFiveDistinctDaysWithServicesAndNoError() {
        #expect(usedOn(days: 5).usageDays.count == 5)
        #expect(ReviewPrompt.shouldAsk(usedOn(days: 5), at: moment()))
        #expect(!ReviewPrompt.shouldAsk(usedOn(days: 4), at: moment()))
    }

    @Test func neverInTheWrongMoment() {
        let state = usedOn(days: 10)
        #expect(!ReviewPrompt.shouldAsk(state, at: moment { $0.demoMode = true }))
        #expect(!ReviewPrompt.shouldAsk(state, at: moment { $0.sessionHadError = true }))
        #expect(!ReviewPrompt.shouldAsk(state, at: moment { $0.serviceCount = 1 }))
        // Right after launch.
        #expect(!ReviewPrompt.shouldAsk(state, at: moment { $0.launchedAt = t0 - 30 }))
        // Right after an action or an error.
        #expect(!ReviewPrompt.shouldAsk(state, at: moment { $0.lastEventAt = t0 - 60 }))
        #expect(ReviewPrompt.shouldAsk(state, at: moment { $0.lastEventAt = t0 - ReviewPrompt.quietAfterEvent }))
    }

    @Test func atMostOncePerVersion() {
        var state = usedOn(days: 10)
        state.markPrompted(version: "1.1")
        #expect(!ReviewPrompt.shouldAsk(state, at: moment()))
        #expect(ReviewPrompt.shouldAsk(state, at: moment { $0.appVersion = "1.2" }))
    }

    @Test func usageDaysAreBoundedAndStored() {
        let state = usedOn(days: 80)
        #expect(state.usageDays.count == 60)
        #expect(ReviewPromptState.decoded(from: state.encoded()) == state)
        #expect(ReviewPromptState.decoded(from: Data("x".utf8)) == ReviewPromptState())
    }
}
