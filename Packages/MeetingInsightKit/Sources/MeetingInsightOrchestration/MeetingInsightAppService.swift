import Foundation
import MeetingInsightDomain
import MeetingInsightRepository
import MeetingInsightResearch

public enum AppServiceError: Error, Equatable, Sendable {
    case invalidScopeDraft
    case scopeNotFound
    case codexUnavailable
}

public actor MeetingInsightAppService: MeetingInsightAppServicing {
    public struct Configuration: Sendable {
        public let scopesFileURL: URL
        public let settingsFileURL: URL
        public let fixtureRootURL: URL?
        public let explicitCodexPath: String?

        public init(
            scopesFileURL: URL,
            settingsFileURL: URL,
            fixtureRootURL: URL? = nil,
            explicitCodexPath: String? = nil
        ) {
            self.scopesFileURL = scopesFileURL
            self.settingsFileURL = settingsFileURL
            self.fixtureRootURL = fixtureRootURL
            self.explicitCodexPath = explicitCodexPath
        }

        public static func environment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Configuration {
            let cli = CLIConfiguration.environment(environment)
            let directory = cli.scopesFileURL.deletingLastPathComponent()
            return Configuration(
                scopesFileURL: cli.scopesFileURL,
                settingsFileURL: directory.appendingPathComponent("settings.json"),
                fixtureRootURL: cli.fixtureRootURL,
                explicitCodexPath: cli.explicitCodexPath
            )
        }
    }

    private let configuration: Configuration
    private let scopeStore: ResearchScopeStore
    private let settingsStore: AppSettingsStore
    private var runningPipelines: [UUID: InvestigationPipeline] = [:]

    public init(configuration: Configuration = .environment()) {
        self.configuration = configuration
        scopeStore = ResearchScopeStore(fileURL: configuration.scopesFileURL)
        settingsStore = AppSettingsStore(fileURL: configuration.settingsFileURL)
    }

    public func bootstrap() async throws -> AppBootstrap {
        let scopes = try await scopeStore.scopes()
        var settings = try await settingsStore.load()
        if let active = settings.activeScopeID, !scopes.contains(where: { $0.id == active }) {
            settings.activeScopeID = nil
            try await settingsStore.save(settings)
        }
        return AppBootstrap(
            scopes: scopes.map(Self.summary),
            activeScopeID: settings.activeScopeID,
            hasAcknowledgedPrivacy: settings.hasAcknowledgedPrivacy,
            codexExecutablePath: settings.codexExecutablePath
        )
    }

    public func saveScope(_ draft: ResearchScopeDraft) async throws -> AppBootstrap {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, (1...3).contains(draft.repositories.count), draft.knowledge.count <= 3 else {
            throw AppServiceError.invalidScopeDraft
        }
        guard draft.repositories.allSatisfy({ !$0.displayName.isEmpty && $0.rootPath.hasPrefix("/") }),
              draft.knowledge.allSatisfy({ !$0.displayName.isEmpty && $0.rootPath.hasPrefix("/") })
        else {
            throw AppServiceError.invalidScopeDraft
        }

        let scope = ResearchScope(
            id: draft.id ?? UUID(),
            name: name,
            repositories: draft.repositories.map { repository in
                RepositoryRoot(
                    id: repository.id,
                    displayName: repository.displayName,
                    rootPath: repository.rootPath,
                    aliases: repository.aliases,
                    environmentLabel: repository.environmentLabel
                )
            },
            knowledgeRoots: draft.knowledge.map { knowledge in
                KnowledgeRoot(
                    id: knowledge.id,
                    displayName: knowledge.displayName,
                    rootPath: knowledge.rootPath,
                    kind: knowledge.kind,
                    includePatterns: knowledge.includePatterns,
                    excludePatterns: knowledge.excludePatterns
                )
            },
            sourcePolicy: SourcePolicy(
                allowedSources: [.code, .test, .config, .git, .localWiki],
                sourcePriority: [.code, .test, .config, .git, .localWiki]
            )
        )
        try await scopeStore.save(scope)
        var settings = try await settingsStore.load()
        if settings.activeScopeID == nil {
            settings.activeScopeID = scope.id
            try await settingsStore.save(settings)
        }
        return try await bootstrap()
    }

    public func selectActiveScope(_ id: UUID?) async throws {
        if let id, try await scopeStore.scopes().contains(where: { $0.id == id }) == false {
            throw AppServiceError.scopeNotFound
        }
        var settings = try await settingsStore.load()
        settings.activeScopeID = id
        try await settingsStore.save(settings)
    }

    public func acknowledgePrivacy() async throws {
        var settings = try await settingsStore.load()
        settings.hasAcknowledgedPrivacy = true
        try await settingsStore.save(settings)
    }

    public func doctor() async -> AppDoctorPresentation {
        do {
            let settings = try await settingsStore.load()
            let executable = try CodexExecutableResolver().resolve(
                explicitPath: settings.codexExecutablePath ?? configuration.explicitCodexPath
            )
            let report = await CodexDoctor().inspect(executableURL: executable)
            return AppDoctorPresentation(
                executablePath: report.executablePath,
                version: report.version ?? "unknown",
                authentication: report.authentication.rawValue,
                issues: report.issues
            )
        } catch {
            return AppDoctorPresentation(
                version: "unknown",
                authentication: "unavailable",
                issues: ["Codex CLIを確認できません。"]
            )
        }
    }

    public func investigate(
        scopeID: UUID,
        question: String,
        requestID: UUID
    ) async throws -> AppInsightPresentation {
        guard let scope = try await scopeStore.scopes().first(where: { $0.id == scopeID }) else {
            throw AppServiceError.scopeNotFound
        }
        let engine = try await makeAgentEngine()
        let pipeline = InvestigationPipeline(agentEngine: engine)
        runningPipelines[requestID] = pipeline
        defer { runningPipelines.removeValue(forKey: requestID) }
        let insight = try await pipeline.investigate(
            scope: scope,
            question: question,
            requestID: requestID
        )
        return Self.presentation(insight)
    }

    public func cancel(requestID: UUID) async {
        await runningPipelines[requestID]?.cancel(requestID: requestID)
    }

    private func makeAgentEngine() async throws -> any AgentEngine {
        if let fixtureRootURL = configuration.fixtureRootURL {
            return try FixtureAgentEngine(fixtureRootURL: fixtureRootURL)
        }
        let settings = try await settingsStore.load()
        let executable = try CodexExecutableResolver().resolve(
            explicitPath: settings.codexExecutablePath ?? configuration.explicitCodexPath
        )
        let report = await CodexDoctor().inspect(executableURL: executable)
        guard report.authentication == .authenticated else { throw AppServiceError.codexUnavailable }
        return CodexAgentEngine(
            executableURL: executable,
            schemaURL: try InsightCardSchema.url()
        )
    }

    private static func summary(_ scope: ResearchScope) -> AppScopeSummary {
        AppScopeSummary(
            id: scope.id,
            name: scope.name,
            repositories: scope.repositories.map {
                AppSourceSummary(name: $0.displayName, detail: $0.environmentLabel)
            },
            knowledge: scope.knowledgeRoots.map {
                AppSourceSummary(name: $0.displayName, detail: $0.kind.rawValue)
            }
        )
    }

    private static func presentation(_ insight: ValidatedInsight) -> AppInsightPresentation {
        let scope = insight.card.scope.repositories.map {
            "\($0.name)@\($0.commitSHA.prefix(8))"
        }.joined(separator: ", ")
        return AppInsightPresentation(
            requestID: insight.id,
            verdict: insight.effectiveVerdict.rawValue,
            headline: insight.card.headline,
            answer: insight.card.answer,
            confidence: insight.computedConfidence,
            scope: scope,
            evidence: insight.validatedEvidence.map {
                AppEvidencePresentation(
                    path: $0.reference.path,
                    lineStart: $0.reference.lineStart,
                    lineEnd: $0.reference.lineEnd,
                    revision: $0.reference.sourceRevision
                )
            }
        )
    }
}
