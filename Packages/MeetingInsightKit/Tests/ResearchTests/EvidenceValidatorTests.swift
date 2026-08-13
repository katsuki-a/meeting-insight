import Foundation
import MeetingInsightDomain
import MeetingInsightRepository
@testable import MeetingInsightResearch
import XCTest

final class EvidenceValidatorTests: XCTestCase {
    func testValidDemoCardKeepsVerdictAndDisplaysOnlyVerifiedEvidence() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let card = try fixture.card(named: "feature-a-paid-and-flag")

        let result = await EvidenceValidator().validate(card, for: fixture.request(for: card))

        XCTAssertEqual(result.effectiveVerdict, .verified)
        XCTAssertEqual(result.validatedEvidence.count, 2)
        XCTAssertEqual(result.card.claims.flatMap(\.evidence).count, 2)
        XCTAssertEqual(result.citationIntegrity, 1)
        XCTAssertEqual(result.computedConfidence, 0.9, accuracy: 0.000_001)
        XCTAssertTrue(result.validationIssues.isEmpty)
    }

    func testRejectsTraversalModifiedQuoteAndOutOfRangeLine() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let valid = cardWithOneEvidence(try fixture.card(named: "feature-a-paid-and-flag"))
        let mutations: [(AgentInsightCard, ValidationIssueCode)] = [
            (
                replacingEvidence(in: valid) { evidence(from: $0, path: "../outside.swift") },
                .invalidPath
            ),
            (
                replacingEvidence(in: valid) {
                    evidence(from: $0, quote: "modified", quoteSHA256: sha256("modified"))
                },
                .quoteMismatch
            ),
            (
                replacingEvidence(in: valid) { evidence(from: $0, lineStart: 10_000, lineEnd: 10_001) },
                .lineRangeInvalid
            ),
            (
                replacingEvidence(in: valid) {
                    evidence(from: $0, quoteSHA256: String(repeating: "0", count: 64))
                },
                .quoteHashMismatch
            ),
        ]

        for (card, issue) in mutations {
            let result = await EvidenceValidator().validate(card, for: fixture.request(for: card))
            XCTAssertEqual(result.effectiveVerdict, .needsHuman)
            XCTAssertTrue(result.validatedEvidence.isEmpty)
            XCTAssertTrue(result.card.claims.isEmpty)
            XCTAssertTrue(result.validationIssues.contains { $0.code == issue })
        }
    }

    func testRejectsSymlinkEscapeWithoutReadingOutsideEvidence() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let original = try fixture.card(named: "feature-a-free-plan")
        let wikiClaim = original.claims[1]
        let valid = AgentInsightCard(
            requestID: original.requestID,
            verdict: original.verdict,
            headline: original.headline,
            answer: original.answer,
            scope: original.scope,
            claims: [
                InsightClaim(
                    text: wikiClaim.text,
                    kind: wikiClaim.kind,
                    confidence: wikiClaim.confidence,
                    evidence: [wikiClaim.evidence[0]]
                )
            ],
            openQuestions: original.openQuestions
        )
        let outside = fixture.temporaryRoot.appendingPathComponent("outside.swift")
        let outsideQuote = "let secret = true"
        try Data(outsideQuote.utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.knowledgeURL.appendingPathComponent("escape.md"),
            withDestinationURL: outside
        )
        let mutated = replacingEvidence(in: valid) {
            evidence(
                from: $0,
                path: "escape.md",
                lineStart: 1,
                lineEnd: 1,
                quote: outsideQuote,
                quoteSHA256: sha256(outsideQuote)
            )
        }

        let result = await EvidenceValidator().validate(mutated, for: fixture.request(for: mutated))

        XCTAssertEqual(result.effectiveVerdict, .needsHuman)
        XCTAssertTrue(result.validatedEvidence.isEmpty)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .pathOutsideRoot })
    }

    func testRejectsKnowledgeEvidenceExcludedByAllowlistPolicy() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let original = try fixture.card(named: "feature-a-free-plan")
        let wikiClaim = original.claims[1]
        let secretQuote = "SECRET=value"
        try Data(secretQuote.utf8).write(
            to: fixture.knowledgeURL.appendingPathComponent(".env")
        )
        let excluded = replacingEvidence(
            in: AgentInsightCard(
                requestID: original.requestID,
                verdict: original.verdict,
                headline: original.headline,
                answer: original.answer,
                scope: original.scope,
                claims: [wikiClaim],
                openQuestions: original.openQuestions
            )
        ) {
            EvidenceReference(
                sourceType: .localWiki,
                sourceName: $0.sourceName,
                sourceRevision: $0.sourceRevision,
                path: ".env",
                lineStart: 1,
                lineEnd: 1,
                quote: secretQuote,
                quoteSHA256: sha256(secretQuote),
                url: nil,
                retrievedAt: nil
            )
        }

        let result = await EvidenceValidator().validate(
            excluded,
            for: fixture.request(for: excluded)
        )

        XCTAssertEqual(result.effectiveVerdict, .needsHuman)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .sourceNotAllowed })
        XCTAssertTrue(result.card.claims.isEmpty)
    }

    func testRejectsPathSwappedToSymlinkBetweenCheckAndOpen() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let card = cardWithOneEvidence(try fixture.card(named: "feature-a-paid-and-flag"))
        let source = fixture.repositoryURL.appendingPathComponent(
            "Sources/DemoApp/FeatureAccessPolicy.swift"
        )
        let outside = fixture.temporaryRoot.appendingPathComponent("replacement.swift")
        try Data(card.claims[0].evidence[0].quote.utf8).write(to: outside)
        let reader = SafeEvidenceFileReader(beforeOpen: {
            try FileManager.default.removeItem(at: source)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        })
        let validator = EvidenceValidator(fileReader: reader)

        let result = await validator.validate(card, for: fixture.request(for: card))

        XCTAssertEqual(result.effectiveVerdict, .needsHuman)
        XCTAssertTrue(result.validatedEvidence.isEmpty)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .pathChangedDuringValidation })
    }

    func testRejectsPathSwappedToAnotherRegularFileBetweenCheckAndOpen() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let card = cardWithOneEvidence(try fixture.card(named: "feature-a-paid-and-flag"))
        let source = fixture.repositoryURL.appendingPathComponent(
            "Sources/DemoApp/FeatureAccessPolicy.swift"
        )
        let originalData = try Data(contentsOf: source)
        let reader = SafeEvidenceFileReader(beforeOpen: {
            try FileManager.default.removeItem(at: source)
            try originalData.write(to: source)
        })

        let result = await EvidenceValidator(fileReader: reader).validate(
            card,
            for: fixture.request(for: card)
        )

        XCTAssertEqual(result.effectiveVerdict, .needsHuman)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .pathChangedDuringValidation })
    }

    func testRejectsRequestIDAndEvidenceRevisionMismatch() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let original = cardWithOneEvidence(try fixture.card(named: "feature-a-paid-and-flag"))
        let wrongRequestCard = AgentInsightCard(
            requestID: UUID(),
            verdict: original.verdict,
            headline: original.headline,
            answer: original.answer,
            scope: original.scope,
            claims: original.claims,
            openQuestions: original.openQuestions
        )
        let wrongRevisionCard = replacingEvidence(in: original) {
            evidence(from: $0, sourceRevision: String(repeating: "0", count: 40))
        }

        let wrongRequest = await EvidenceValidator().validate(
            wrongRequestCard,
            for: fixture.request(for: original)
        )
        let wrongRevision = await EvidenceValidator().validate(
            wrongRevisionCard,
            for: fixture.request(for: wrongRevisionCard)
        )

        XCTAssertEqual(wrongRequest.effectiveVerdict, .needsHuman)
        XCTAssertTrue(wrongRequest.validationIssues.contains { $0.code == .requestIDMismatch })
        XCTAssertEqual(wrongRevision.effectiveVerdict, .needsHuman)
        XCTAssertTrue(wrongRevision.validationIssues.contains { $0.code == .revisionMismatch })
    }

    func testRejectsRepositoryDirtyStateChangedAfterSnapshot() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let card = try fixture.card(named: "feature-a-paid-and-flag")
        try Data("changed\n".utf8).write(
            to: fixture.repositoryURL.appendingPathComponent("uncommitted.txt")
        )

        let result = await EvidenceValidator().validate(card, for: fixture.request(for: card))

        XCTAssertEqual(result.effectiveVerdict, .needsHuman)
        XCTAssertTrue(result.validationIssues.contains { $0.code == .repositoryChanged })
        XCTAssertTrue(result.card.claims.isEmpty)
    }

    func testNonNotFoundCardWithoutEvidenceNeedsHumanButNotFoundRemainsValid() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let verified = try fixture.card(named: "feature-a-paid-and-flag")
        let noEvidence = AgentInsightCard(
            requestID: verified.requestID,
            verdict: .verified,
            headline: verified.headline,
            answer: verified.answer,
            scope: verified.scope,
            claims: [],
            openQuestions: verified.openQuestions
        )
        let notFound = try fixture.card(named: "feature-b-retention")

        let rejected = await EvidenceValidator().validate(
            noEvidence,
            for: fixture.request(for: noEvidence)
        )
        let accepted = await EvidenceValidator().validate(
            notFound,
            for: fixture.request(for: notFound)
        )

        XCTAssertEqual(rejected.effectiveVerdict, .needsHuman)
        XCTAssertTrue(rejected.validationIssues.contains { $0.code == .claimWithoutEvidence })
        XCTAssertEqual(accepted.effectiveVerdict, .notFound)
        XCTAssertTrue(accepted.validationIssues.isEmpty)
    }
}
