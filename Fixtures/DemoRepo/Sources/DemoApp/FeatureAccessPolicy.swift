public struct AccountContext: Sendable, Equatable {
    public let isPaidPlan: Bool

    public init(isPaidPlan: Bool) {
        self.isPaidPlan = isPaidPlan
    }
}

public enum FeatureAccessPolicy {
    public static func canUseFeatureA(
        account: AccountContext,
        remoteFlagEnabled: Bool
    ) -> Bool {
        account.isPaidPlan && remoteFlagEnabled
    }
}
