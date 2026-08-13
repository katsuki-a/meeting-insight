import Foundation
import MeetingInsightDomain

public struct AppSourceSummary: Codable, Equatable, Sendable {
    public let name: String
    public let detail: String

    public init(name: String, detail: String) {
        self.name = name
        self.detail = detail
    }
}

public struct AppScopeSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let repositories: [AppSourceSummary]
    public let knowledge: [AppSourceSummary]

    public init(
        id: UUID,
        name: String,
        repositories: [AppSourceSummary],
        knowledge: [AppSourceSummary]
    ) {
        self.id = id
        self.name = name
        self.repositories = repositories
        self.knowledge = knowledge
    }
}

public struct AppBootstrap: Codable, Equatable, Sendable {
    public let scopes: [AppScopeSummary]
    public let activeScopeID: UUID?
    public let hasAcknowledgedPrivacy: Bool
    public let codexExecutablePath: String?

    public init(
        scopes: [AppScopeSummary],
        activeScopeID: UUID?,
        hasAcknowledgedPrivacy: Bool,
        codexExecutablePath: String?
    ) {
        self.scopes = scopes
        self.activeScopeID = activeScopeID
        self.hasAcknowledgedPrivacy = hasAcknowledgedPrivacy
        self.codexExecutablePath = codexExecutablePath
    }
}

public struct RepositoryDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var rootPath: String
    public var aliases: [String]
    public var environmentLabel: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        rootPath: String,
        aliases: [String] = [],
        environmentLabel: String = "local-head"
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.aliases = aliases
        self.environmentLabel = environmentLabel
    }
}

public struct KnowledgeDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var rootPath: String
    public var kind: KnowledgeKind
    public var includePatterns: [String]
    public var excludePatterns: [String]

    public init(
        id: UUID = UUID(),
        displayName: String,
        rootPath: String,
        kind: KnowledgeKind = .markdown,
        includePatterns: [String] = [],
        excludePatterns: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.kind = kind
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
    }
}

public struct ResearchScopeDraft: Equatable, Sendable {
    public var id: UUID?
    public var name: String
    public var repositories: [RepositoryDraft]
    public var knowledge: [KnowledgeDraft]

    public init(
        id: UUID? = nil,
        name: String,
        repositories: [RepositoryDraft],
        knowledge: [KnowledgeDraft] = []
    ) {
        self.id = id
        self.name = name
        self.repositories = repositories
        self.knowledge = knowledge
    }
}

public struct AppDoctorPresentation: Codable, Equatable, Sendable {
    public let executablePath: String?
    public let version: String
    public let authentication: String
    public let issues: [String]

    public init(
        executablePath: String? = nil,
        version: String,
        authentication: String,
        issues: [String]
    ) {
        self.executablePath = executablePath
        self.version = version
        self.authentication = authentication
        self.issues = issues
    }
}

public struct AppEvidencePresentation: Codable, Equatable, Sendable {
    public let path: String
    public let lineStart: Int
    public let lineEnd: Int
    public let revision: String

    public init(path: String, lineStart: Int, lineEnd: Int, revision: String) {
        self.path = path
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.revision = revision
    }
}

public struct AppInsightPresentation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { requestID }

    public let requestID: UUID
    public let verdict: String
    public let headline: String
    public let answer: String
    public let confidence: Double
    public let scope: String
    public let evidence: [AppEvidencePresentation]

    public init(
        requestID: UUID,
        verdict: String,
        headline: String,
        answer: String,
        confidence: Double,
        scope: String,
        evidence: [AppEvidencePresentation]
    ) {
        self.requestID = requestID
        self.verdict = verdict
        self.headline = headline
        self.answer = answer
        self.confidence = confidence
        self.scope = scope
        self.evidence = evidence
    }
}

public protocol MeetingInsightAppServicing: Sendable {
    func bootstrap() async throws -> AppBootstrap
    func saveScope(_ draft: ResearchScopeDraft) async throws -> AppBootstrap
    func selectActiveScope(_ id: UUID?) async throws
    func acknowledgePrivacy() async throws
    func doctor() async -> AppDoctorPresentation
    func investigate(
        scopeID: UUID,
        question: String,
        requestID: UUID
    ) async throws -> AppInsightPresentation
    func cancel(requestID: UUID) async
}
