import Testing
@testable import PatchNodeCore

@Suite("ServiceCategory")
struct ServiceCategoryTests {
    @Test func everyKindIsInExactlyOneCategory() {
        let listed = ServiceCategory.allCases.flatMap(\.kinds)
        #expect(listed.count == ServiceKind.allCases.count)
        #expect(Set(listed) == Set(ServiceKind.allCases))
    }

    @Test func categoryOfAKindListsIt() {
        for kind in ServiceKind.allCases {
            #expect(kind.category.kinds.contains(kind))
        }
    }
}
