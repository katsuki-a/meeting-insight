import CryptoKit
import Foundation
import MeetingInsightDomain
import MeetingInsightRepository

public struct EvidenceValidator: Sendable {
    private let git: GitProcess
    private let knowledgeProvider: LocalKnowledgeProvider
    private let fileReader: any EvidenceFileReading
    private let confidenceCalculator: ConfidenceCalculatorV1
    private let now: @Sendable () -> Date

    public init(
        git: GitProcess = GitProcess(),
        knowledgeProvider: LocalKnowledgeProvider = LocalKnowledgeProvider(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.git = git
        self.knowledgeProvider = knowledgeProvider
        self.fileReader = SafeEvidenceFileReader()
        self.confidenceCalculator = ConfidenceCalculatorV1()
        self.now = now
    }

    init(
        git: GitProcess = GitProcess(),
        knowledgeProvider: LocalKnowledgeProvider = LocalKnowledgeProvider(),
        fileReader: any EvidenceFileReading,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.git = git
        self.knowledgeProvider = knowledgeProvider
        self.fileReader = fileReader
        self.confidenceCalculator = ConfidenceCalculatorV1()
        self.now = now
    }

    public func validate(
        _ card: AgentInsightCard,
        for request: InvestigationRequest
    ) async -> ValidatedInsight {
        var issues: [ValidationIssue] = []
        if card.requestID != request.id {
            issues.append(ValidationIssue(code: .requestIDMismatch))
        }
        validateScope(card.scope, request: request, issues: &issues)
        await validateSourceState(request: request, issues: &issues)
        if hasFatalGlobalIssue(issues) {
            return failedInsight(card: card, request: request, issues: issues)
        }

        var sanitizedClaims: [InsightClaim] = []
        var validatedEvidence: [ValidatedEvidence] = []
        for (claimIndex, claim) in card.claims.enumerated() {
            var references: [EvidenceReference] = []
            for (evidenceIndex, reference) in claim.evidence.enumerated() {
                if let validated = validate(
                    reference,
                    cardScope: card.scope,
                    request: request,
                    claimIndex: claimIndex,
                    evidenceIndex: evidenceIndex,
                    issues: &issues
                ) {
                    references.append(validated)
                    validatedEvidence.append(
                        ValidatedEvidence(claimIndex: claimIndex, reference: validated)
                    )
                }
            }
            if references.isEmpty {
                issues.append(
                    ValidationIssue(code: .claimWithoutEvidence, claimIndex: claimIndex)
                )
            } else {
                sanitizedClaims.append(
                    InsightClaim(
                        text: claim.text,
                        kind: claim.kind,
                        confidence: claim.confidence,
                        evidence: references
                    )
                )
            }
        }

        if card.claims.isEmpty, card.verdict != .notFound {
            issues.append(ValidationIssue(code: .claimWithoutEvidence))
        }
        await validateSourceState(request: request, issues: &issues)
        if hasFatalGlobalIssue(issues) {
            return failedInsight(card: card, request: request, issues: unique(issues))
        }

        let effectiveVerdict: Verdict
        if card.claims.isEmpty, card.verdict == .notFound {
            effectiveVerdict = .notFound
        } else if sanitizedClaims.isEmpty {
            effectiveVerdict = .needsHuman
        } else if sanitizedClaims.count < card.claims.count {
            effectiveVerdict = .partial
        } else {
            effectiveVerdict = card.verdict
        }
        let sanitizedCard = makeSanitizedCard(
            from: card,
            request: request,
            claims: sanitizedClaims,
            verdict: effectiveVerdict
        )
        let references = validatedEvidence.map(\.reference)
        let calculatedConfidence = confidenceCalculator.calculate(
            evidence: references,
            repositoriesAreClean: request.repositories.allSatisfy { !$0.isDirty },
            hasRelevantAmbiguity: !card.openQuestions.isEmpty
                || sanitizedClaims.count < card.claims.count
        )
        return ValidatedInsight(
            card: sanitizedCard,
            validatedEvidence: validatedEvidence,
            effectiveVerdict: effectiveVerdict,
            computedConfidence: calculatedConfidence,
            confidenceVersion: confidenceCalculator.version,
            citationIntegrity: 1,
            validationIssues: unique(issues),
            completedAt: now()
        )
    }

    private func validateScope(
        _ scope: InsightScope,
        request: InvestigationRequest,
        issues: inout [ValidationIssue]
    ) {
        for repository in scope.repositories {
            let matches = request.repositories.filter { $0.root.displayName == repository.name }
            guard matches.count == 1, let snapshot = matches.first,
                  snapshot.commitSHA.caseInsensitiveCompare(repository.commitSHA) == .orderedSame,
                  snapshot.isDirty == repository.dirtyWorktree
            else {
                issues.append(ValidationIssue(code: .scopeMismatch))
                continue
            }
        }
        for knowledge in scope.knowledgeRoots {
            let matches = request.knowledge.filter { $0.root.displayName == knowledge.name }
            guard matches.count == 1, let snapshot = matches.first,
                  snapshot.revision.caseInsensitiveCompare(knowledge.revision) == .orderedSame
            else {
                issues.append(ValidationIssue(code: .scopeMismatch))
                continue
            }
        }
        if let firstRepository = scope.repositories.first,
           let snapshot = request.repositories.first(where: { $0.root.displayName == firstRepository.name }),
           scope.environment != snapshot.root.environmentLabel {
            issues.append(ValidationIssue(code: .scopeMismatch))
        }
    }

    private func validateSourceState(
        request: InvestigationRequest,
        issues: inout [ValidationIssue]
    ) async {
        for snapshot in request.repositories {
            let rootURL = URL(fileURLWithPath: snapshot.root.rootPath, isDirectory: true)
            do {
                let head = try await git.run(["rev-parse", "HEAD"], in: rootURL)
                let status = try await git.run(["status", "--porcelain=v1"], in: rootURL)
                if head.caseInsensitiveCompare(snapshot.commitSHA) != .orderedSame
                    || (!status.isEmpty) != snapshot.isDirty {
                    issues.append(ValidationIssue(code: .repositoryChanged))
                }
            } catch {
                issues.append(ValidationIssue(code: .repositoryChanged))
            }
        }
        for snapshot in request.knowledge {
            do {
                let current = try knowledgeProvider.snapshot(
                    snapshot.root,
                    capturedAt: snapshot.capturedAt
                )
                if current.revision.caseInsensitiveCompare(snapshot.revision) != .orderedSame {
                    issues.append(ValidationIssue(code: .knowledgeChanged))
                }
            } catch {
                issues.append(ValidationIssue(code: .knowledgeChanged))
            }
        }
    }

    private func validate(
        _ reference: EvidenceReference,
        cardScope: InsightScope,
        request: InvestigationRequest,
        claimIndex: Int,
        evidenceIndex: Int,
        issues: inout [ValidationIssue]
    ) -> EvidenceReference? {
        guard request.allowedSources.contains(reference.sourceType) else {
            issues.append(issue(.sourceNotAllowed, claimIndex, evidenceIndex))
            return nil
        }

        let sourceRoot: URL
        switch reference.sourceType {
        case .code, .test, .config, .git:
            let snapshots = request.repositories.filter {
                $0.root.displayName == reference.sourceName
            }
            guard snapshots.count == 1, let snapshot = snapshots.first,
                  cardScope.repositories.contains(where: { $0.name == reference.sourceName })
            else {
                issues.append(issue(.sourceNotInScope, claimIndex, evidenceIndex))
                return nil
            }
            guard snapshot.commitSHA.caseInsensitiveCompare(reference.sourceRevision) == .orderedSame else {
                issues.append(issue(.revisionMismatch, claimIndex, evidenceIndex))
                return nil
            }
            sourceRoot = URL(fileURLWithPath: snapshot.root.rootPath, isDirectory: true)
        case .localWiki:
            let snapshots = request.knowledge.filter {
                $0.root.displayName == reference.sourceName
            }
            guard snapshots.count == 1, let snapshot = snapshots.first,
                  cardScope.knowledgeRoots.contains(where: { $0.name == reference.sourceName })
            else {
                issues.append(issue(.sourceNotInScope, claimIndex, evidenceIndex))
                return nil
            }
            guard snapshot.revision.caseInsensitiveCompare(reference.sourceRevision) == .orderedSame else {
                issues.append(issue(.revisionMismatch, claimIndex, evidenceIndex))
                return nil
            }
            do {
                _ = try knowledgeProvider.read(
                    relativePath: reference.path,
                    in: snapshot.root
                )
            } catch let error as RepositoryError {
                let code: ValidationIssueCode
                switch error {
                case .invalidRelativePath: code = .invalidPath
                case .pathOutsideRoot: code = .pathOutsideRoot
                case .pathNotAllowed: code = .sourceNotAllowed
                default: code = .pathUnreadable
                }
                issues.append(issue(code, claimIndex, evidenceIndex))
                return nil
            } catch {
                issues.append(issue(.pathUnreadable, claimIndex, evidenceIndex))
                return nil
            }
            sourceRoot = URL(fileURLWithPath: snapshot.root.rootPath, isDirectory: true)
        case .deepwiki:
            issues.append(issue(.sourceNotInScope, claimIndex, evidenceIndex))
            return nil
        }

        let data: Data
        do {
            data = try fileReader.read(relativePath: reference.path, rootURL: sourceRoot)
        } catch let error as EvidenceFileReadError {
            let code: ValidationIssueCode
            switch error {
            case .invalidPath: code = .invalidPath
            case .outsideRoot: code = .pathOutsideRoot
            case .unreadable: code = .pathUnreadable
            case .changedDuringValidation: code = .pathChangedDuringValidation
            }
            issues.append(issue(code, claimIndex, evidenceIndex))
            return nil
        } catch {
            issues.append(issue(.pathUnreadable, claimIndex, evidenceIndex))
            return nil
        }
        guard let content = String(data: data, encoding: .utf8) else {
            issues.append(issue(.pathUnreadable, claimIndex, evidenceIndex))
            return nil
        }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if content.hasSuffix("\n"), lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard reference.lineStart >= 1,
              reference.lineStart <= reference.lineEnd,
              reference.lineEnd <= lines.count
        else {
            issues.append(issue(.lineRangeInvalid, claimIndex, evidenceIndex))
            return nil
        }
        let quote = lines[(reference.lineStart - 1)...(reference.lineEnd - 1)]
            .joined(separator: "\n")
        guard quote == reference.quote else {
            issues.append(issue(.quoteMismatch, claimIndex, evidenceIndex))
            return nil
        }
        let digest = SHA256.hash(data: Data(quote.utf8)).hexString
        guard digest.caseInsensitiveCompare(reference.quoteSHA256) == .orderedSame else {
            issues.append(issue(.quoteHashMismatch, claimIndex, evidenceIndex))
            return nil
        }
        return reference
    }

    private func makeSanitizedCard(
        from card: AgentInsightCard,
        request: InvestigationRequest,
        claims: [InsightClaim],
        verdict: Verdict
    ) -> AgentInsightCard {
        let downgraded = verdict != card.verdict
        return AgentInsightCard(
            requestID: card.requestID,
            verdict: verdict,
            headline: downgraded ? "一部の根拠だけを再検証できました" : card.headline,
            answer: downgraded
                ? "検証できなかった根拠を除外しました。残る根拠を確認してください。"
                : card.answer,
            scope: safeScope(request),
            claims: claims,
            openQuestions: card.openQuestions
        )
    }

    private func failedInsight(
        card: AgentInsightCard,
        request: InvestigationRequest,
        issues: [ValidationIssue]
    ) -> ValidatedInsight {
        let safeCard = AgentInsightCard(
            requestID: request.id,
            verdict: .needsHuman,
            headline: "根拠を再検証できません",
            answer: "表示できる根拠がないため、人による確認が必要です。",
            scope: safeScope(request),
            claims: [],
            openQuestions: card.openQuestions
        )
        return ValidatedInsight(
            card: safeCard,
            validatedEvidence: [],
            effectiveVerdict: .needsHuman,
            computedConfidence: 0,
            confidenceVersion: confidenceCalculator.version,
            citationIntegrity: 1,
            validationIssues: unique(issues),
            completedAt: now()
        )
    }

    private func safeScope(_ request: InvestigationRequest) -> InsightScope {
        InsightScope(
            environment: request.repositories.first?.root.environmentLabel ?? "unknown",
            repositories: request.repositories.map {
                InsightRepository(
                    name: $0.root.displayName,
                    commitSHA: $0.commitSHA,
                    dirtyWorktree: $0.isDirty
                )
            },
            knowledgeRoots: request.knowledge.map {
                InsightKnowledgeRoot(
                    name: $0.root.displayName,
                    revision: $0.revision,
                    revisionKind: .contentDigest
                )
            },
            productionRevisionVerified: false
        )
    }

    private func hasFatalGlobalIssue(_ issues: [ValidationIssue]) -> Bool {
        issues.contains {
            $0.claimIndex == nil && [
                .requestIDMismatch,
                .scopeMismatch,
                .repositoryChanged,
                .knowledgeChanged,
            ].contains($0.code)
        }
    }

    private func issue(
        _ code: ValidationIssueCode,
        _ claimIndex: Int,
        _ evidenceIndex: Int
    ) -> ValidationIssue {
        ValidationIssue(
            code: code,
            claimIndex: claimIndex,
            evidenceIndex: evidenceIndex
        )
    }

    private func unique(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        var seen: Set<String> = []
        return issues.filter {
            seen.insert("\($0.code.rawValue):\($0.claimIndex ?? -1):\($0.evidenceIndex ?? -1)").inserted
        }
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
