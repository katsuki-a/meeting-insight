import Foundation

public enum Verdict: String, CaseIterable, Codable, Sendable {
    case verified
    case contradicted
    case partial
    case notFound = "not_found"
    case needsHuman = "needs_human"
}

public enum InsightClaimKind: String, CaseIterable, Codable, Sendable {
    case observation
    case inference
}

public enum KnowledgeRevisionKind: String, CaseIterable, Codable, Sendable {
    case gitCommit = "git_commit"
    case contentDigest = "content_digest"
    case retrievedAt = "retrieved_at"
}

public struct AgentInsightCard: Codable, Equatable, Sendable {
    public static let schemaPropertyNames: Set<String> = [
        "schema_version",
        "request_id",
        "verdict",
        "headline",
        "answer",
        "scope",
        "claims",
        "open_questions"
    ]
    public static let requiredSchemaPropertyNames = schemaPropertyNames

    public let schemaVersion: Int
    public let requestID: UUID
    public let verdict: Verdict
    public let headline: String
    public let answer: String
    public let scope: InsightScope
    public let claims: [InsightClaim]
    public let openQuestions: [String]

    public init(
        schemaVersion: Int = InsightCardSchema.version,
        requestID: UUID,
        verdict: Verdict,
        headline: String,
        answer: String,
        scope: InsightScope,
        claims: [InsightClaim],
        openQuestions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.verdict = verdict
        self.headline = headline
        self.answer = answer
        self.scope = scope
        self.claims = claims
        self.openQuestions = openQuestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        verdict = try container.decode(Verdict.self, forKey: .verdict)
        headline = try container.decode(String.self, forKey: .headline)
        answer = try container.decode(String.self, forKey: .answer)
        scope = try container.decode(InsightScope.self, forKey: .scope)
        claims = try container.decode([InsightClaim].self, forKey: .claims)
        openQuestions = try container.decode([String].self, forKey: .openQuestions)

        try ContractValidation.require(
            schemaVersion == InsightCardSchema.version,
            codingPath: decoder.codingPath + [CodingKeys.schemaVersion],
            description: "Unsupported schema version: \(schemaVersion)"
        )
        try ContractValidation.requireString(
            headline,
            maximum: 80,
            codingPath: decoder.codingPath + [CodingKeys.headline]
        )
        try ContractValidation.requireString(
            answer,
            maximum: 500,
            codingPath: decoder.codingPath + [CodingKeys.answer]
        )
        for (index, question) in openQuestions.enumerated() {
            try ContractValidation.requireString(
                question,
                maximum: 300,
                codingPath: decoder.codingPath + [CodingKeys.openQuestions, AnyCodingKey(intValue: index)!]
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case verdict
        case headline
        case answer
        case scope
        case claims
        case openQuestions = "open_questions"
    }
}

public struct InsightScope: Codable, Equatable, Sendable {
    public let environment: String
    public let repositories: [InsightRepository]
    public let knowledgeRoots: [InsightKnowledgeRoot]
    public let productionRevisionVerified: Bool

    public init(
        environment: String,
        repositories: [InsightRepository],
        knowledgeRoots: [InsightKnowledgeRoot],
        productionRevisionVerified: Bool
    ) {
        self.environment = environment
        self.repositories = repositories
        self.knowledgeRoots = knowledgeRoots
        self.productionRevisionVerified = productionRevisionVerified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        environment = try container.decode(String.self, forKey: .environment)
        repositories = try container.decode([InsightRepository].self, forKey: .repositories)
        knowledgeRoots = try container.decode([InsightKnowledgeRoot].self, forKey: .knowledgeRoots)
        productionRevisionVerified = try container.decode(Bool.self, forKey: .productionRevisionVerified)

        try ContractValidation.requireString(
            environment,
            codingPath: decoder.codingPath + [CodingKeys.environment]
        )
        try ContractValidation.require(
            !repositories.isEmpty,
            codingPath: decoder.codingPath + [CodingKeys.repositories],
            description: "At least one repository is required"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case environment
        case repositories
        case knowledgeRoots = "knowledge_roots"
        case productionRevisionVerified = "production_revision_verified"
    }
}

public struct InsightRepository: Codable, Equatable, Sendable {
    public let name: String
    public let commitSHA: String
    public let dirtyWorktree: Bool

    public init(name: String, commitSHA: String, dirtyWorktree: Bool) {
        self.name = name
        self.commitSHA = commitSHA
        self.dirtyWorktree = dirtyWorktree
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        commitSHA = try container.decode(String.self, forKey: .commitSHA)
        dirtyWorktree = try container.decode(Bool.self, forKey: .dirtyWorktree)

        try ContractValidation.requireString(
            name,
            codingPath: decoder.codingPath + [CodingKeys.name]
        )
        try ContractValidation.requireHex(
            commitSHA,
            lengths: 7...64,
            codingPath: decoder.codingPath + [CodingKeys.commitSHA]
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case commitSHA = "commit_sha"
        case dirtyWorktree = "dirty_worktree"
    }
}

public struct InsightKnowledgeRoot: Codable, Equatable, Sendable {
    public let name: String
    public let revision: String
    public let revisionKind: KnowledgeRevisionKind

    public init(name: String, revision: String, revisionKind: KnowledgeRevisionKind) {
        self.name = name
        self.revision = revision
        self.revisionKind = revisionKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        revision = try container.decode(String.self, forKey: .revision)
        revisionKind = try container.decode(KnowledgeRevisionKind.self, forKey: .revisionKind)

        try ContractValidation.requireString(name, codingPath: decoder.codingPath + [CodingKeys.name])
        try ContractValidation.requireString(
            revision,
            codingPath: decoder.codingPath + [CodingKeys.revision]
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case revision
        case revisionKind = "revision_kind"
    }
}

public struct InsightClaim: Codable, Equatable, Sendable {
    public let text: String
    public let kind: InsightClaimKind
    public let confidence: Double
    public let evidence: [EvidenceReference]

    public init(
        text: String,
        kind: InsightClaimKind,
        confidence: Double,
        evidence: [EvidenceReference]
    ) {
        self.text = text
        self.kind = kind
        self.confidence = confidence
        self.evidence = evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        kind = try container.decode(InsightClaimKind.self, forKey: .kind)
        confidence = try container.decode(Double.self, forKey: .confidence)
        evidence = try container.decode([EvidenceReference].self, forKey: .evidence)

        try ContractValidation.requireString(
            text,
            maximum: 500,
            codingPath: decoder.codingPath + [CodingKeys.text]
        )
        try ContractValidation.require(
            confidence.isFinite && (0...1).contains(confidence),
            codingPath: decoder.codingPath + [CodingKeys.confidence],
            description: "Confidence must be between zero and one"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case kind
        case confidence
        case evidence
    }
}

public struct EvidenceReference: Codable, Equatable, Sendable {
    public let sourceType: EvidenceSourceType
    public let sourceName: String
    public let sourceRevision: String
    public let path: String
    public let lineStart: Int
    public let lineEnd: Int
    public let quote: String
    public let quoteSHA256: String
    public let url: URL?
    public let retrievedAt: Date?

    public init(
        sourceType: EvidenceSourceType,
        sourceName: String,
        sourceRevision: String,
        path: String,
        lineStart: Int,
        lineEnd: Int,
        quote: String,
        quoteSHA256: String,
        url: URL?,
        retrievedAt: Date?
    ) {
        self.sourceType = sourceType
        self.sourceName = sourceName
        self.sourceRevision = sourceRevision
        self.path = path
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.quote = quote
        self.quoteSHA256 = quoteSHA256
        self.url = url
        self.retrievedAt = retrievedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.strictContainer(keyedBy: CodingKeys.self)
        sourceType = try container.decode(EvidenceSourceType.self, forKey: .sourceType)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        sourceRevision = try container.decode(String.self, forKey: .sourceRevision)
        path = try container.decode(String.self, forKey: .path)
        lineStart = try container.decode(Int.self, forKey: .lineStart)
        lineEnd = try container.decode(Int.self, forKey: .lineEnd)
        quote = try container.decode(String.self, forKey: .quote)
        quoteSHA256 = try container.decode(String.self, forKey: .quoteSHA256)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        retrievedAt = try container.decodeIfPresent(Date.self, forKey: .retrievedAt)

        try ContractValidation.requireString(
            sourceName,
            codingPath: decoder.codingPath + [CodingKeys.sourceName]
        )
        try ContractValidation.requireString(
            sourceRevision,
            codingPath: decoder.codingPath + [CodingKeys.sourceRevision]
        )
        try ContractValidation.requireString(path, codingPath: decoder.codingPath + [CodingKeys.path])
        try ContractValidation.require(
            lineStart >= 1 && lineEnd >= 1,
            codingPath: decoder.codingPath + [CodingKeys.lineStart],
            description: "Line values must be greater than or equal to one"
        )
        try ContractValidation.requireString(
            quote,
            maximum: 2_000,
            codingPath: decoder.codingPath + [CodingKeys.quote]
        )
        try ContractValidation.requireHex(
            quoteSHA256,
            lengths: 64...64,
            codingPath: decoder.codingPath + [CodingKeys.quoteSHA256]
        )
        if let url {
            try ContractValidation.require(
                url.scheme != nil,
                codingPath: decoder.codingPath + [CodingKeys.url],
                description: "URL must be absolute"
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceType = "source_type"
        case sourceName = "source_name"
        case sourceRevision = "source_revision"
        case path
        case lineStart = "line_start"
        case lineEnd = "line_end"
        case quote
        case quoteSHA256 = "quote_sha256"
        case url
        case retrievedAt = "retrieved_at"
    }
}
