import Testing
@testable import PatchNodeCore

@Suite("HealthLevel")
struct HealthLevelTests {
    @Test func levelsAreOrderedOkWarningCritical() {
        #expect(HealthLevel.ok < .warning)
        #expect(HealthLevel.warning < .critical)
        #expect(HealthLevel.ok < .critical)
        #expect(!(HealthLevel.critical < .ok))
        #expect(!(HealthLevel.warning < .warning))
    }

    @Test func sortingAndMaxFollowSeverity() {
        #expect([HealthLevel.critical, .ok, .warning].sorted() == [.ok, .warning, .critical])
        #expect([HealthLevel.ok, .critical, .warning].max() == .critical)
        #expect(HealthLevel.allCases == [.ok, .warning, .critical])
    }
}
