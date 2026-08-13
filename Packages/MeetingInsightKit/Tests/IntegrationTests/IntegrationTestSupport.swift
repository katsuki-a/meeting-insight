import Foundation
import MeetingInsightDomain
import MeetingInsightRepository

func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

struct IntegrationFixture {
    let temporaryRoot: URL
    let repositoryURL: URL
    let knowledgeURL: URL
    let scope: ResearchScope

    init() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-insight-integration-\(UUID().uuidString)", isDirectory: true)
        repositoryURL = temporaryRoot.appendingPathComponent("Demo Repo 日本語", isDirectory: true)
        knowledgeURL = temporaryRoot.appendingPathComponent("Demo Wiki 日本語", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try run(
            executable: repositoryRoot().appendingPathComponent("Scripts/make-demo-repo.sh"),
            arguments: [repositoryURL.path],
            directory: repositoryRoot()
        )
        try FileManager.default.copyItem(
            at: repositoryRoot().appendingPathComponent("Fixtures/DemoWiki"),
            to: knowledgeURL
        )
        scope = ResearchScope(
            id: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!,
            name: "Demo Product",
            repositories: [
                RepositoryRoot(
                    id: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!,
                    displayName: "DemoRepo",
                    rootPath: repositoryURL.path,
                    aliases: ["demo", "Feature A", "Feature B"],
                    environmentLabel: "synthetic-main"
                )
            ],
            knowledgeRoots: [
                KnowledgeRoot(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!,
                    displayName: "DemoWiki",
                    rootPath: knowledgeURL.path,
                    kind: .llmWiki,
                    includePatterns: ["**/*.md"],
                    excludePatterns: []
                )
            ],
            sourcePolicy: SourcePolicy(
                allowedSources: [.code, .test, .config, .git, .localWiki],
                sourcePriority: [.code, .test, .config, .git, .localWiki]
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func scenarios() throws -> [FixtureScenario] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("Fixtures/questions.json"))
        return try JSONDecoder().decode(FixtureScenarioDocument.self, from: data).scenarios
    }
}

struct FixtureScenarioDocument: Decodable {
    let scenarios: [FixtureScenario]
}

struct FixtureScenario: Decodable {
    let id: String
    let requestID: UUID
    let spokenQuestion: String
    let expectedVerdict: Verdict
    let requiredEvidencePaths: [String]
    let expectedCard: String

    enum CodingKeys: String, CodingKey {
        case id
        case requestID = "request_id"
        case spokenQuestion = "spoken_question"
        case expectedVerdict = "expected_verdict"
        case requiredEvidencePaths = "required_evidence_paths"
        case expectedCard = "expected_card"
    }
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
        throw IntegrationTestError.commandFailed(String(decoding: errorData, as: UTF8.self))
    }
    return String(decoding: outputData, as: UTF8.self)
}

private enum IntegrationTestError: Error {
    case commandFailed(String)
}
