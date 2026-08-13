import MeetingInsightDomain

public struct ConfidenceCalculatorV1: Sendable {
    public let version = 1

    public init() {}

    public func calculate(
        evidence: [EvidenceReference],
        repositoriesAreClean: Bool,
        hasRelevantAmbiguity: Bool
    ) -> Double {
        var confidence = 0.35
        let sourceTypes = Set(evidence.map(\.sourceType))
        if sourceTypes.contains(.code) {
            confidence += 0.20
        }
        if sourceTypes.contains(.test) {
            confidence += 0.15
        }
        if sourceTypes.contains(.config) {
            confidence += 0.10
        }
        let independentFiles = Set(evidence.map { "\($0.sourceName)\u{0}\($0.path)" })
        if independentFiles.count >= 2 {
            confidence += 0.10
        }
        if repositoriesAreClean {
            confidence += 0.10
        } else {
            confidence -= 0.20
        }
        if !evidence.isEmpty && evidence.allSatisfy({ [.localWiki, .deepwiki].contains($0.sourceType) }) {
            confidence -= 0.20
        }
        if hasRelevantAmbiguity {
            confidence -= 0.25
        }
        return min(1, max(0, confidence))
    }
}
