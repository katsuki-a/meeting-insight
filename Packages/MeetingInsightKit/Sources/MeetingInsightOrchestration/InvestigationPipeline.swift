import Foundation
import MeetingInsightDomain
import MeetingInsightRepository
import MeetingInsightResearch

public enum InvestigationPipelineError: Error, Equatable, Sendable {
    case scopeHasNoRepository
    case ambiguousPrimaryRepository([String])
}

public struct PreparedInvestigation: Sendable {
    public let request: InvestigationRequest
    public let knowledgeExcerpts: [KnowledgeExcerpt]

    public init(request: InvestigationRequest, knowledgeExcerpts: [KnowledgeExcerpt]) {
        self.request = request
        self.knowledgeExcerpts = knowledgeExcerpts
    }
}

public struct ResearchSnapshotter: Sendable {
    private let repoResolver: RepoResolver
    private let knowledgeProvider: LocalKnowledgeProvider
    private let now: @Sendable () -> Date

    public init(
        repoResolver: RepoResolver = RepoResolver(),
        knowledgeProvider: LocalKnowledgeProvider = LocalKnowledgeProvider(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repoResolver = repoResolver
        self.knowledgeProvider = knowledgeProvider
        self.now = now
    }

    public func snapshot(scope: ResearchScope) async throws -> ResearchSnapshot {
        let capturedAt = now()
        var repositories: [RepoSnapshot] = []
        for repository in scope.repositories {
            repositories.append(try await repoResolver.snapshot(repository))
        }
        let knowledge = try scope.knowledgeRoots.map {
            try knowledgeProvider.snapshot($0, capturedAt: capturedAt)
        }
        return ResearchSnapshot(
            scopeID: scope.id,
            repositories: repositories,
            knowledge: knowledge,
            capturedAt: capturedAt
        )
    }
}

public struct InvestigationPipeline: Sendable {
    private let agentEngine: any AgentEngine
    private let snapshotter: ResearchSnapshotter
    private let knowledgeProvider: LocalKnowledgeProvider
    private let evidenceValidator: EvidenceValidator

    public init(
        agentEngine: any AgentEngine,
        snapshotter: ResearchSnapshotter = ResearchSnapshotter(),
        knowledgeProvider: LocalKnowledgeProvider = LocalKnowledgeProvider(),
        evidenceValidator: EvidenceValidator = EvidenceValidator()
    ) {
        self.agentEngine = agentEngine
        self.snapshotter = snapshotter
        self.knowledgeProvider = knowledgeProvider
        self.evidenceValidator = evidenceValidator
    }

    public func investigate(
        scope: ResearchScope,
        question: String,
        context: String = "",
        requestID: UUID = UUID()
    ) async throws -> ValidatedInsight {
        let prepared = try await prepare(
            scope: scope,
            question: question,
            context: context,
            requestID: requestID
        )
        let card = try await agentEngine.investigate(
            AgentInvestigation(
                request: prepared.request,
                conversationContext: context,
                knowledgeExcerpts: prepared.knowledgeExcerpts
            )
        )
        return await evidenceValidator.validate(card, for: prepared.request)
    }

    public func prepare(
        scope: ResearchScope,
        question: String,
        context: String = "",
        requestID: UUID = UUID(),
        repositoryHint: String? = nil
    ) async throws -> PreparedInvestigation {
        let snapshot = try await snapshotter.snapshot(scope: scope)
        let primary = try primaryRepository(
            in: snapshot.repositories,
            question: question,
            repositoryHint: repositoryHint
        )
        let excerpts = try selectKnowledgeExcerpts(
            question: question,
            snapshots: snapshot.knowledge
        )
        let entities = entities(in: question, repositories: scope.repositories)
        let request = InvestigationRequest(
            id: requestID,
            scopeID: scope.id,
            trigger: .manualText,
            spokenQuestion: question,
            contextBefore: context.isEmpty ? [] : [context],
            entities: entities,
            repositories: [primary],
            knowledge: snapshot.knowledge,
            deadline: .seconds(90),
            allowedSources: scope.sourcePolicy.allowedSources
        )
        return PreparedInvestigation(request: request, knowledgeExcerpts: excerpts)
    }

    public func validate(
        _ card: AgentInsightCard,
        scope: ResearchScope
    ) async throws -> ValidatedInsight {
        let prepared = try await prepare(
            scope: scope,
            question: "",
            requestID: card.requestID,
            repositoryHint: card.scope.repositories.first?.name
        )
        return await evidenceValidator.validate(card, for: prepared.request)
    }

    public func cancel(requestID: UUID) async {
        await agentEngine.cancel(requestID: requestID)
    }

    private func primaryRepository(
        in snapshots: [RepoSnapshot],
        question: String,
        repositoryHint: String?
    ) throws -> RepoSnapshot {
        guard !snapshots.isEmpty else { throw InvestigationPipelineError.scopeHasNoRepository }
        if snapshots.count == 1 { return snapshots[0] }
        if let repositoryHint {
            let hinted = snapshots.filter { $0.root.displayName == repositoryHint }
            if hinted.count == 1, let match = hinted.first { return match }
        }
        let normalizedQuestion = normalize(question)
        let matches = snapshots.filter { snapshot in
            ([snapshot.root.displayName] + snapshot.root.aliases).contains { alias in
                let normalizedAlias = normalize(alias)
                return !normalizedAlias.isEmpty && normalizedQuestion.contains(normalizedAlias)
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw InvestigationPipelineError.ambiguousPrimaryRepository(
                snapshots.map(\.root.displayName).sorted()
            )
        }
        return match
    }

    private func selectKnowledgeExcerpts(
        question: String,
        snapshots: [KnowledgeSnapshot]
    ) throws -> [KnowledgeExcerpt] {
        let terms = searchTerms(question)
        var candidates: [(score: Int, excerpt: KnowledgeExcerpt)] = []
        for snapshot in snapshots {
            for document in try knowledgeProvider.documents(in: snapshot.root) {
                let content = normalize(document.content)
                let score = terms.reduce(into: 0) { total, term in
                    if content.contains(term) { total += term.count }
                }
                guard score > 0 else { continue }
                candidates.append(
                    (
                        score,
                        KnowledgeExcerpt(
                            sourceName: snapshot.root.displayName,
                            revision: snapshot.revision,
                            relativePath: document.relativePath,
                            content: document.content
                        )
                    )
                )
            }
        }
        return candidates
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.excerpt.relativePath < $1.excerpt.relativePath
            }
            .prefix(6)
            .map(\.excerpt)
    }

    private func entities(in question: String, repositories: [RepositoryRoot]) -> [String] {
        let normalizedQuestion = normalize(question)
        var values: [String] = []
        for repository in repositories {
            for alias in [repository.displayName] + repository.aliases
            where normalizedQuestion.contains(normalize(alias)) {
                values.append(alias)
            }
        }
        values.append(contentsOf: featureTerms(question))
        return Array(Set(values)).sorted()
    }

    private func searchTerms(_ question: String) -> [String] {
        var terms = featureTerms(question).map(normalize)
        let words = question.split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }
        terms.append(contentsOf: words.map { normalize(String($0)) }.filter { $0.count >= 3 })
        return Array(Set(terms.filter { !$0.isEmpty })).sorted()
    }

    private func featureTerms(_ question: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)feature\s+[a-z0-9_-]+"#
        ) else { return [] }
        let range = NSRange(question.startIndex..<question.endIndex, in: question)
        return expression.matches(in: question, range: range).compactMap { match in
            Range(match.range, in: question).map { String(question[$0]) }
        }
    }

    private func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }
}
