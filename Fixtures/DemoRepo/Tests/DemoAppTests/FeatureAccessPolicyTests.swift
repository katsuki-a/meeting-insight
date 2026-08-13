import XCTest
@testable import DemoApp

final class FeatureAccessPolicyTests: XCTestCase {
    func testFeatureARequiresPaidPlanAndEnabledFlag() {
        XCTAssertTrue(
            FeatureAccessPolicy.canUseFeatureA(
                account: AccountContext(isPaidPlan: true),
                remoteFlagEnabled: true
            )
        )
        XCTAssertFalse(
            FeatureAccessPolicy.canUseFeatureA(
                account: AccountContext(isPaidPlan: false),
                remoteFlagEnabled: true
            )
        )
        XCTAssertFalse(
            FeatureAccessPolicy.canUseFeatureA(
                account: AccountContext(isPaidPlan: true),
                remoteFlagEnabled: false
            )
        )
    }
}
