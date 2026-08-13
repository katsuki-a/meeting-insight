import Foundation

public enum ValidationIssueCode: String, Codable, Equatable, Sendable {
    case requestIDMismatch = "request_id_mismatch"
    case scopeMismatch = "scope_mismatch"
    case sourceNotAllowed = "source_not_allowed"
    case sourceNotInScope = "source_not_in_scope"
    case revisionMismatch = "revision_mismatch"
    case invalidPath = "invalid_path"
    case pathOutsideRoot = "path_outside_root"
    case pathUnreadable = "path_unreadable"
    case pathChangedDuringValidation = "path_changed_during_validation"
    case lineRangeInvalid = "line_range_invalid"
    case quoteMismatch = "quote_mismatch"
    case quoteHashMismatch = "quote_hash_mismatch"
    case claimWithoutEvidence = "claim_without_evidence"
    case repositoryChanged = "repository_changed"
    case knowledgeChanged = "knowledge_changed"
}

public struct ValidationIssue: Codable, Equatable, Sendable {
    public let code: ValidationIssueCode
    public let claimIndex: Int?
    public let evidenceIndex: Int?

    public init(
        code: ValidationIssueCode,
        claimIndex: Int? = nil,
        evidenceIndex: Int? = nil
    ) {
        self.code = code
        self.claimIndex = claimIndex
        self.evidenceIndex = evidenceIndex
    }
}

public struct ValidatedEvidence: Codable, Equatable, Sendable {
    public let claimIndex: Int
    public let reference: EvidenceReference

    public init(claimIndex: Int, reference: EvidenceReference) {
        self.claimIndex = claimIndex
        self.reference = reference
    }
}

public struct ValidatedInsight: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { card.requestID }

    public let card: AgentInsightCard
    public let validatedEvidence: [ValidatedEvidence]
    public let effectiveVerdict: Verdict
    public let computedConfidence: Double
    public let confidenceVersion: Int
    public let citationIntegrity: Double
    public let validationIssues: [ValidationIssue]
    public let completedAt: Date

    public init(
        card: AgentInsightCard,
        validatedEvidence: [ValidatedEvidence],
        effectiveVerdict: Verdict,
        computedConfidence: Double,
        confidenceVersion: Int,
        citationIntegrity: Double,
        validationIssues: [ValidationIssue],
        completedAt: Date
    ) {
        self.card = card
        self.validatedEvidence = validatedEvidence
        self.effectiveVerdict = effectiveVerdict
        self.computedConfidence = computedConfidence
        self.confidenceVersion = confidenceVersion
        self.citationIntegrity = citationIntegrity
        self.validationIssues = validationIssues
        self.completedAt = completedAt
    }
}
