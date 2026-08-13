import Foundation

public enum KnowledgeKind: String, CaseIterable, Codable, Sendable {
    case markdown
    case adr
    case llmWiki = "llm_wiki"
}

public enum EvidenceSourceType: String, CaseIterable, Codable, Hashable, Sendable {
    case code
    case test
    case config
    case git
    case localWiki = "local_wiki"
    case deepwiki
}

public enum TriggerType: String, CaseIterable, Codable, Sendable {
    case manualText = "manual_text"
    case manualRecentTranscript = "manual_recent_transcript"
    case explicitQuestion = "explicit_question"
}

public struct SourcePolicy: Codable, Equatable, Sendable {
    public let allowedSources: Set<EvidenceSourceType>
    public let sourcePriority: [EvidenceSourceType]

    public init(
        allowedSources: Set<EvidenceSourceType>,
        sourcePriority: [EvidenceSourceType]
    ) {
        self.allowedSources = allowedSources
        self.sourcePriority = sourcePriority
    }
}

public struct RepositoryRoot: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let rootPath: String
    public let aliases: [String]
    public let environmentLabel: String

    public init(
        id: UUID,
        displayName: String,
        rootPath: String,
        aliases: [String],
        environmentLabel: String
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.aliases = aliases
        self.environmentLabel = environmentLabel
    }
}

public struct KnowledgeRoot: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let rootPath: String
    public let kind: KnowledgeKind
    public let includePatterns: [String]
    public let excludePatterns: [String]

    public init(
        id: UUID,
        displayName: String,
        rootPath: String,
        kind: KnowledgeKind,
        includePatterns: [String],
        excludePatterns: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.kind = kind
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
    }
}

public struct ResearchScope: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let repositories: [RepositoryRoot]
    public let knowledgeRoots: [KnowledgeRoot]
    public let sourcePolicy: SourcePolicy

    public init(
        id: UUID,
        name: String,
        repositories: [RepositoryRoot],
        knowledgeRoots: [KnowledgeRoot],
        sourcePolicy: SourcePolicy
    ) {
        self.id = id
        self.name = name
        self.repositories = repositories
        self.knowledgeRoots = knowledgeRoots
        self.sourcePolicy = sourcePolicy
    }
}

public struct RepoSnapshot: Codable, Equatable, Sendable {
    public let root: RepositoryRoot
    public let commitSHA: String
    public let branch: String?
    public let isDirty: Bool
    public let capturedAt: Date

    public init(
        root: RepositoryRoot,
        commitSHA: String,
        branch: String?,
        isDirty: Bool,
        capturedAt: Date
    ) {
        self.root = root
        self.commitSHA = commitSHA
        self.branch = branch
        self.isDirty = isDirty
        self.capturedAt = capturedAt
    }
}

public struct KnowledgeSnapshot: Codable, Equatable, Sendable {
    public let root: KnowledgeRoot
    public let revision: String
    public let fileCount: Int
    public let capturedAt: Date

    public init(
        root: KnowledgeRoot,
        revision: String,
        fileCount: Int,
        capturedAt: Date
    ) {
        self.root = root
        self.revision = revision
        self.fileCount = fileCount
        self.capturedAt = capturedAt
    }
}

public struct InvestigationRequest: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let scopeID: UUID
    public let trigger: TriggerType
    public let spokenQuestion: String
    public let contextBefore: [String]
    public let entities: [String]
    public let repositories: [RepoSnapshot]
    public let knowledge: [KnowledgeSnapshot]
    public let deadline: Duration
    public let allowedSources: Set<EvidenceSourceType>

    public init(
        id: UUID,
        scopeID: UUID,
        trigger: TriggerType,
        spokenQuestion: String,
        contextBefore: [String],
        entities: [String],
        repositories: [RepoSnapshot],
        knowledge: [KnowledgeSnapshot],
        deadline: Duration,
        allowedSources: Set<EvidenceSourceType>
    ) {
        self.id = id
        self.scopeID = scopeID
        self.trigger = trigger
        self.spokenQuestion = spokenQuestion
        self.contextBefore = contextBefore
        self.entities = entities
        self.repositories = repositories
        self.knowledge = knowledge
        self.deadline = deadline
        self.allowedSources = allowedSources
    }
}
