import MeetingInsightDomain
@testable import MeetingInsightResearch
import XCTest

final class ConfidenceCalculatorTests: XCTestCase {
    func testVersionOneWeightsAreClampedAndDoNotUseAgentConfidence() {
        let calculator = ConfidenceCalculatorV1()
        let references = [
            reference(type: .code, path: "Sources/Feature.swift"),
            reference(type: .test, path: "Tests/FeatureTests.swift"),
            reference(type: .config, path: "Config/features.json"),
        ]

        XCTAssertEqual(
            calculator.calculate(
                evidence: references,
                repositoriesAreClean: true,
                hasRelevantAmbiguity: false
            ),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            calculator.calculate(
                evidence: [reference(type: .localWiki, path: "feature.md")],
                repositoriesAreClean: false,
                hasRelevantAmbiguity: true
            ),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(calculator.version, 1)
    }

    private func reference(type: EvidenceSourceType, path: String) -> EvidenceReference {
        EvidenceReference(
            sourceType: type,
            sourceName: type == .localWiki ? "DemoWiki" : "DemoRepo",
            sourceRevision: "0123456789abcdef0123456789abcdef01234567",
            path: path,
            lineStart: 1,
            lineEnd: 1,
            quote: "line",
            quoteSHA256: String(repeating: "a", count: 64),
            url: nil,
            retrievedAt: nil
        )
    }
}
