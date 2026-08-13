import Foundation
import MeetingInsightDomain
import MeetingInsightRepository
import MeetingInsightResearch

public struct CLIConfiguration: Sendable {
    public let scopesFileURL: URL
    public let explicitCodexPath: String?
    public let fixtureRootURL: URL?

    public init(
        scopesFileURL: URL,
        explicitCodexPath: String? = nil,
        fixtureRootURL: URL? = nil
    ) {
        self.scopesFileURL = scopesFileURL
        self.explicitCodexPath = explicitCodexPath
        self.fixtureRootURL = fixtureRootURL
    }

    public static func environment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CLIConfiguration {
        let scopesURL: URL
        if let configured = environment["MEETING_INSIGHT_SCOPES_FILE"], configured.hasPrefix("/") {
            scopesURL = URL(fileURLWithPath: configured)
        } else {
            scopesURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MeetingInsight/scopes.json")
        }
        return CLIConfiguration(
            scopesFileURL: scopesURL,
            explicitCodexPath: environment["MEETING_INSIGHT_CODEX_PATH"],
            fixtureRootURL: environment["MEETING_INSIGHT_FIXTURE_ROOT"].flatMap { value in
                value.hasPrefix("/") ? URL(fileURLWithPath: value, isDirectory: true) : nil
            }
        )
    }
}

public struct CLIExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public struct MeetingInsightCLIApplication: Sendable {
    public static let help = """
    Meeting Insight

    USAGE: meeting-insight <command> [options]

    COMMANDS:
      doctor [--json]
      scope list [--json]
      scope inspect --scope <id-or-name> [--json]
      snapshot --scope <id-or-name> [--json]
      validate --scope <id-or-name> --card <json-or-path> [--json]
      ask --scope <id-or-name> --question <text> [--context <text>] [--json]
      help

    ENVIRONMENT:
      MEETING_INSIGHT_SCOPES_FILE  Absolute path to the Research Scope store
      MEETING_INSIGHT_CODEX_PATH   Absolute path to the Codex executable
      MEETING_INSIGHT_FIXTURE_ROOT Use the recorded fake engine from this fixture root
    """

    private let configuration: CLIConfiguration
    private let injectedAgentEngine: (any AgentEngine)?
    private let resolveExecutable: @Sendable (String?) throws -> URL
    private let inspectExecutable: @Sendable (URL) async -> CodexDoctorReport

    public init(
        configuration: CLIConfiguration = .environment(),
        agentEngine: (any AgentEngine)? = nil,
        resolveExecutable: @escaping @Sendable (String?) throws -> URL = {
            try CodexExecutableResolver().resolve(explicitPath: $0)
        },
        inspectExecutable: @escaping @Sendable (URL) async -> CodexDoctorReport = {
            await CodexDoctor().inspect(executableURL: $0)
        }
    ) {
        self.configuration = configuration
        injectedAgentEngine = agentEngine
        self.resolveExecutable = resolveExecutable
        self.inspectExecutable = inspectExecutable
    }

    public func execute(arguments: [String]) async -> CLIExecutionResult {
        guard let command = arguments.first else { return success(Self.help) }
        do {
            switch command {
            case "help", "--help", "-h":
                guard arguments.count == 1 else { throw CLIUsageError.unexpectedArguments }
                return success(Self.help + "\n")
            case "doctor":
                return try await doctor(arguments: Array(arguments.dropFirst()))
            case "scope":
                return try await scope(arguments: Array(arguments.dropFirst()))
            case "snapshot":
                return try await snapshot(arguments: Array(arguments.dropFirst()))
            case "validate":
                return try await validate(arguments: Array(arguments.dropFirst()))
            case "ask":
                return try await ask(arguments: Array(arguments.dropFirst()))
            default:
                throw CLIUsageError.unknownCommand(command)
            }
        } catch let error as CLIUsageError {
            return CLIExecutionResult(
                exitCode: 64,
                standardError: "\(error.message)\n\n\(Self.help)\n"
            )
        } catch {
            return CLIExecutionResult(
                exitCode: 1,
                standardError: "Command failed: \(safeDescription(error))\n"
            )
        }
    }

    private func doctor(arguments: [String]) async throws -> CLIExecutionResult {
        let options = try Options(arguments, values: [], flags: ["--json"])
        let executable = try resolveExecutable(configuration.explicitCodexPath)
        let report = await inspectExecutable(executable)
        if options.hasFlag("--json") { return try jsonSuccess(report) }
        let version = report.version ?? "unknown"
        return success(
            "executable: \(report.executablePath)\nversion: \(version)\nauthentication: \(report.authentication.rawValue)\n"
        )
    }

    private func scope(arguments: [String]) async throws -> CLIExecutionResult {
        guard let subcommand = arguments.first else { throw CLIUsageError.missingArgument("scope subcommand") }
        let store = ResearchScopeStore(fileURL: configuration.scopesFileURL)
        switch subcommand {
        case "list":
            let options = try Options(Array(arguments.dropFirst()), values: [], flags: ["--json"])
            let scopes = try await store.scopes()
            if options.hasFlag("--json") { return try jsonSuccess(scopes) }
            let text = scopes.isEmpty
                ? "No Research Scopes configured.\n"
                : scopes.map { "\($0.id.uuidString.lowercased())\t\($0.name)" }.joined(separator: "\n") + "\n"
            return success(text)
        case "inspect":
            let options = try Options(
                Array(arguments.dropFirst()),
                values: ["--scope"],
                flags: ["--json"]
            )
            let selected = try await requiredScope(options: options, store: store)
            if options.hasFlag("--json") { return try jsonSuccess(selected) }
            return success(render(scope: selected))
        default:
            throw CLIUsageError.unknownSubcommand(subcommand)
        }
    }

    private func snapshot(arguments: [String]) async throws -> CLIExecutionResult {
        let options = try Options(arguments, values: ["--scope"], flags: ["--json"])
        let store = ResearchScopeStore(fileURL: configuration.scopesFileURL)
        let selected = try await requiredScope(options: options, store: store)
        let snapshot = try await ResearchSnapshotter().snapshot(scope: selected)
        if options.hasFlag("--json") { return try jsonSuccess(snapshot) }
        return success(render(snapshot: snapshot))
    }

    private func validate(arguments: [String]) async throws -> CLIExecutionResult {
        let options = try Options(
            arguments,
            values: ["--scope", "--card"],
            flags: ["--json"]
        )
        let store = ResearchScopeStore(fileURL: configuration.scopesFileURL)
        let selected = try await requiredScope(options: options, store: store)
        let cardValue = try options.requiredValue("--card")
        let card = try decodeCard(cardValue)
        let engine = injectedAgentEngine ?? UnavailableAgentEngine()
        let insight = try await InvestigationPipeline(agentEngine: engine).validate(card, scope: selected)
        if options.hasFlag("--json") { return try jsonSuccess(insight) }
        return success(render(insight: insight))
    }

    private func ask(arguments: [String]) async throws -> CLIExecutionResult {
        let options = try Options(
            arguments,
            values: ["--scope", "--question", "--context"],
            flags: ["--json"]
        )
        let store = ResearchScopeStore(fileURL: configuration.scopesFileURL)
        let selected = try await requiredScope(options: options, store: store)
        let question = try options.requiredValue("--question")
        let context = options.value("--context") ?? ""
        let engine = try await agentEngine()
        let insight = try await InvestigationPipeline(agentEngine: engine).investigate(
            scope: selected,
            question: question,
            context: context
        )
        if options.hasFlag("--json") { return try jsonSuccess(insight) }
        return success(render(insight: insight))
    }

    private func requiredScope(
        options: Options,
        store: ResearchScopeStore
    ) async throws -> ResearchScope {
        let identifier = try options.requiredValue("--scope")
        guard let scope = try await store.scope(idOrName: identifier) else {
            throw CLIRuntimeError.scopeNotFound
        }
        return scope
    }

    private func agentEngine() async throws -> any AgentEngine {
        if let injectedAgentEngine { return injectedAgentEngine }
        if let fixtureRootURL = configuration.fixtureRootURL {
            return try FixtureAgentEngine(fixtureRootURL: fixtureRootURL)
        }
        let executable = try resolveExecutable(configuration.explicitCodexPath)
        let report = await inspectExecutable(executable)
        guard report.authentication == .authenticated else {
            throw CLIRuntimeError.codexUnavailable
        }
        return CodexAgentEngine(
            executableURL: executable,
            schemaURL: try InsightCardSchema.url()
        )
    }

    private func decodeCard(_ value: String) throws -> AgentInsightCard {
        let data: Data
        if value.hasPrefix("/"), FileManager.default.fileExists(atPath: value) {
            data = try Data(contentsOf: URL(fileURLWithPath: value))
        } else {
            data = Data(value.utf8)
        }
        return try InsightCardCoding.decoder().decode(AgentInsightCard.self, from: data)
    }

    private func render(scope: ResearchScope) -> String {
        var lines = ["scope: \(scope.name)", "id: \(scope.id.uuidString.lowercased())"]
        lines += scope.repositories.map { "repository: \($0.displayName)" }
        lines += scope.knowledgeRoots.map { "knowledge: \($0.displayName)" }
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(snapshot: ResearchSnapshot) -> String {
        var lines = snapshot.repositories.map { repository in
            "repository: \(repository.root.displayName)@\(repository.commitSHA) dirty=\(repository.isDirty)"
        }
        lines += snapshot.knowledge.map { knowledge in
            "knowledge: \(knowledge.root.displayName)@\(knowledge.revision) files=\(knowledge.fileCount)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(insight: ValidatedInsight) -> String {
        var lines = [
            "verdict: \(insight.effectiveVerdict.rawValue)",
            "headline: \(insight.card.headline)",
            "answer: \(insight.card.answer)",
            "confidence: \(String(format: "%.2f", insight.computedConfidence))",
        ]
        lines += insight.card.scope.repositories.map { repository in
            "scope: \(repository.name)@\(repository.commitSHA) dirty=\(repository.dirtyWorktree)"
        }
        lines += insight.validatedEvidence.map { evidence in
            let reference = evidence.reference
            return "evidence: \(reference.path):\(reference.lineStart)-\(reference.lineEnd) @ \(reference.sourceRevision)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func jsonSuccess<Value: Encodable>(_ value: Value) throws -> CLIExecutionResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return success(String(decoding: data, as: UTF8.self) + "\n")
    }

    private func success(_ output: String) -> CLIExecutionResult {
        CLIExecutionResult(exitCode: 0, standardOutput: output)
    }

    private func safeDescription(_ error: Error) -> String {
        switch error {
        case let error as CLIUsageError: return error.message
        case CLIRuntimeError.scopeNotFound: return "Research Scope was not found."
        case CLIRuntimeError.codexUnavailable: return "Codex CLI is unavailable or unauthenticated."
        case InvestigationPipelineError.scopeHasNoRepository: return "Research Scope has no repository."
        case InvestigationPipelineError.ambiguousPrimaryRepository(let names):
            return "Primary repository is ambiguous: \(names.joined(separator: ", "))"
        case CodexExecutableResolverError.notFound: return "Codex executable was not found."
        case CodexExecutableResolverError.invalidExplicitPath: return "Configured Codex path is invalid."
        case DecodingError.dataCorrupted, DecodingError.keyNotFound,
             DecodingError.typeMismatch, DecodingError.valueNotFound:
            return "The supplied JSON does not match the Insight Card contract."
        default: return String(describing: type(of: error))
        }
    }
}

private enum CLIRuntimeError: Error {
    case scopeNotFound
    case codexUnavailable
}

private enum CLIUsageError: Error {
    case unknownCommand(String)
    case unknownSubcommand(String)
    case unknownOption(String)
    case duplicateOption(String)
    case missingArgument(String)
    case unexpectedArguments

    var message: String {
        switch self {
        case .unknownCommand(let value): "Unknown command: \(value)"
        case .unknownSubcommand(let value): "Unknown subcommand: \(value)"
        case .unknownOption(let value): "Unknown option: \(value)"
        case .duplicateOption(let value): "Duplicate option: \(value)"
        case .missingArgument(let value): "Missing argument: \(value)"
        case .unexpectedArguments: "Unexpected arguments."
        }
    }
}

private struct Options {
    private let values: [String: String]
    private let flags: Set<String>

    init(_ arguments: [String], values allowedValues: Set<String>, flags allowedFlags: Set<String>) throws {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if allowedFlags.contains(argument) {
                guard flags.insert(argument).inserted else {
                    throw CLIUsageError.duplicateOption(argument)
                }
                index += 1
            } else if allowedValues.contains(argument) {
                guard values[argument] == nil else { throw CLIUsageError.duplicateOption(argument) }
                guard index + 1 < arguments.count else {
                    throw CLIUsageError.missingArgument(argument)
                }
                values[argument] = arguments[index + 1]
                index += 2
            } else {
                throw CLIUsageError.unknownOption(argument)
            }
        }
        self.values = values
        self.flags = flags
    }

    func value(_ name: String) -> String? { values[name] }
    func hasFlag(_ name: String) -> Bool { flags.contains(name) }

    func requiredValue(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw CLIUsageError.missingArgument(name)
        }
        return value
    }
}

private struct UnavailableAgentEngine: AgentEngine {
    let id = "unavailable"

    func investigate(_ investigation: AgentInvestigation) async throws -> AgentInsightCard {
        throw CLIRuntimeError.codexUnavailable
    }

    func cancel(requestID: UUID) async {}
}
