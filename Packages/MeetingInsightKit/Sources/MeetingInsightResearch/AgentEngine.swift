import Foundation
import MeetingInsightDomain

public struct AgentInvestigation: Sendable {
    public let request: InvestigationRequest
    public let conversationContext: String
    public let knowledgeExcerpts: [KnowledgeExcerpt]

    public init(
        request: InvestigationRequest,
        conversationContext: String,
        knowledgeExcerpts: [KnowledgeExcerpt]
    ) {
        self.request = request
        self.conversationContext = conversationContext
        self.knowledgeExcerpts = knowledgeExcerpts
    }
}

public protocol AgentEngine: Sendable {
    var id: String { get }
    func investigate(_ investigation: AgentInvestigation) async throws -> AgentInsightCard
    func cancel(requestID: UUID) async
}

public actor CodexAgentEngine: AgentEngine {
    public nonisolated let id = "codex"

    private let executableURL: URL
    private let schemaURL: URL
    private let runner: CodexProcessRunner
    private let promptBuilder: AgentPromptBuilderV1

    public init(
        executableURL: URL,
        schemaURL: URL,
        runner: CodexProcessRunner = CodexProcessRunner(),
        promptBuilder: AgentPromptBuilderV1 = AgentPromptBuilderV1()
    ) {
        self.executableURL = executableURL
        self.schemaURL = schemaURL
        self.runner = runner
        self.promptBuilder = promptBuilder
    }

    public func investigate(_ investigation: AgentInvestigation) async throws -> AgentInsightCard {
        guard let repository = investigation.request.repositories.first else {
            throw AgentEngineError.missingPrimaryRepository
        }
        let prompt = try promptBuilder.build(
            request: investigation.request,
            conversationContext: investigation.conversationContext,
            knowledgeExcerpts: investigation.knowledgeExcerpts
        )
        return try await runner.run(
            CodexRunRequest(
                requestID: investigation.request.id,
                executableURL: executableURL,
                repositoryURL: URL(fileURLWithPath: repository.root.rootPath, isDirectory: true),
                schemaURL: schemaURL,
                prompt: prompt
            )
        ).card
    }

    public func cancel(requestID: UUID) async {
        await runner.cancel(requestID: requestID)
    }
}

public enum AgentEngineError: Error, Equatable, Sendable {
    case missingPrimaryRepository
    case unknownFixtureQuestion
    case malformedFixture
}

public struct FixtureAgentEngine: AgentEngine {
    public let id = "fixture"
    private let cardsByQuestion: [String: AgentInsightCard]

    public init(fixtureRootURL: URL) throws {
        let data = try Data(
            contentsOf: fixtureRootURL.appendingPathComponent("Fixtures/questions.json")
        )
        let document = try JSONDecoder().decode(FixtureQuestionDocument.self, from: data)
        var cards: [String: AgentInsightCard] = [:]
        for scenario in document.scenarios {
            let cardData = try Data(
                contentsOf: fixtureRootURL.appendingPathComponent(scenario.expectedCard)
            )
            cards[scenario.spokenQuestion] = try InsightCardCoding.decoder().decode(
                AgentInsightCard.self,
                from: cardData
            )
        }
        guard cards.count == document.scenarios.count else {
            throw AgentEngineError.malformedFixture
        }
        cardsByQuestion = cards
    }

    public func investigate(_ investigation: AgentInvestigation) async throws -> AgentInsightCard {
        guard let card = cardsByQuestion[investigation.request.spokenQuestion] else {
            throw AgentEngineError.unknownFixtureQuestion
        }
        return AgentInsightCard(
            requestID: investigation.request.id,
            verdict: card.verdict,
            headline: card.headline,
            answer: card.answer,
            scope: card.scope,
            claims: card.claims,
            openQuestions: card.openQuestions
        )
    }

    public func cancel(requestID: UUID) async {}
}

private struct FixtureQuestionDocument: Decodable {
    let scenarios: [FixtureQuestion]
}

private struct FixtureQuestion: Decodable {
    let spokenQuestion: String
    let expectedCard: String

    enum CodingKeys: String, CodingKey {
        case spokenQuestion = "spoken_question"
        case expectedCard = "expected_card"
    }
}
