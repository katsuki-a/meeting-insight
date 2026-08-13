import CryptoKit
import Foundation
import MeetingInsightDomain
import MeetingInsightRepository

struct ResearchFixture {
    let temporaryRoot: URL
    let repositoryURL: URL
    let knowledgeURL: URL
    let repositorySnapshot: RepoSnapshot
    let knowledgeSnapshot: KnowledgeSnapshot

    init() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-insight-research-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        repositoryURL = temporaryRoot.appendingPathComponent("DemoRepo", isDirectory: true)
        knowledgeURL = temporaryRoot.appendingPathComponent("DemoWiki", isDirectory: true)
        try run(
            executable: repositoryRoot.appendingPathComponent("Scripts/make-demo-repo.sh"),
            arguments: [repositoryURL.path],
            directory: repositoryRoot
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("Fixtures/DemoWiki"),
            to: knowledgeURL
        )

        let repository = RepositoryRoot(
            id: UUID(),
            displayName: "DemoRepo",
            rootPath: repositoryURL.path,
            aliases: ["demo"],
            environmentLabel: "synthetic-main"
        )
        let commit = try run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["rev-parse", "HEAD"],
            directory: repositoryURL
        )
        repositorySnapshot = RepoSnapshot(
            root: repository,
            commitSHA: commit,
            branch: "main",
            isDirty: false,
            capturedAt: Date(timeIntervalSince1970: 1_786_512_345)
        )
        let knowledge = KnowledgeRoot(
            id: UUID(),
            displayName: "DemoWiki",
            rootPath: knowledgeURL.path,
            kind: .llmWiki,
            includePatterns: ["**/*.md"],
            excludePatterns: []
        )
        knowledgeSnapshot = try LocalKnowledgeProvider().snapshot(
            knowledge,
            capturedAt: Date(timeIntervalSince1970: 1_786_512_345)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func card(named name: String) throws -> AgentInsightCard {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("Fixtures/ExpectedCards/\(name).json")
        )
        return try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: data)
    }

    func request(for card: AgentInsightCard) -> InvestigationRequest {
        InvestigationRequest(
            id: card.requestID,
            scopeID: UUID(),
            trigger: .manualText,
            spokenQuestion: "Synthetic question",
            contextBefore: [],
            entities: ["Feature A"],
            repositories: [repositorySnapshot],
            knowledge: [knowledgeSnapshot],
            deadline: .seconds(35),
            allowedSources: [.code, .test, .config, .git, .localWiki]
        )
    }
}

func replacingEvidence(
    in card: AgentInsightCard,
    claimIndex: Int = 0,
    evidenceIndex: Int = 0,
    transform: (EvidenceReference) -> EvidenceReference
) -> AgentInsightCard {
    var claims = card.claims
    let claim = claims[claimIndex]
    var evidence = claim.evidence
    evidence[evidenceIndex] = transform(evidence[evidenceIndex])
    claims[claimIndex] = InsightClaim(
        text: claim.text,
        kind: claim.kind,
        confidence: claim.confidence,
        evidence: evidence
    )
    return AgentInsightCard(
        requestID: card.requestID,
        verdict: card.verdict,
        headline: card.headline,
        answer: card.answer,
        scope: card.scope,
        claims: claims,
        openQuestions: card.openQuestions
    )
}

func cardWithOneEvidence(_ card: AgentInsightCard) -> AgentInsightCard {
    let claim = card.claims[0]
    return AgentInsightCard(
        requestID: card.requestID,
        verdict: card.verdict,
        headline: card.headline,
        answer: card.answer,
        scope: card.scope,
        claims: [
            InsightClaim(
                text: claim.text,
                kind: claim.kind,
                confidence: claim.confidence,
                evidence: [claim.evidence[0]]
            )
        ],
        openQuestions: card.openQuestions
    )
}

func evidence(
    from original: EvidenceReference,
    sourceRevision: String? = nil,
    path: String? = nil,
    lineStart: Int? = nil,
    lineEnd: Int? = nil,
    quote: String? = nil,
    quoteSHA256: String? = nil
) -> EvidenceReference {
    EvidenceReference(
        sourceType: original.sourceType,
        sourceName: original.sourceName,
        sourceRevision: sourceRevision ?? original.sourceRevision,
        path: path ?? original.path,
        lineStart: lineStart ?? original.lineStart,
        lineEnd: lineEnd ?? original.lineEnd,
        quote: quote ?? original.quote,
        quoteSHA256: quoteSHA256 ?? original.quoteSHA256,
        url: original.url,
        retrievedAt: original.retrievedAt
    )
}

func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

@discardableResult
private func run(executable: URL, arguments: [String], directory: URL) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw ResearchTestError.commandFailed(String(decoding: errorData, as: UTF8.self))
    }
    return String(decoding: outputData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private enum ResearchTestError: Error {
    case commandFailed(String)
}
