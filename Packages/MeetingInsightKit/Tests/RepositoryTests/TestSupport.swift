import Foundation
import MeetingInsightDomain

struct TemporaryDirectory {
    let url: URL

    init(name: String = "workspace") throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-insight-tests-\(UUID().uuidString)", isDirectory: true)
        url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@discardableResult
func runGit(_ arguments: [String], at directory: URL) throws -> String {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()

    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let error = standardError.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw TestSupportError.commandFailed(
            String(decoding: error, as: UTF8.self)
        )
    }
    return String(decoding: output, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func makeGitRepository(at url: URL) throws -> String {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try runGit(["init", "--quiet", "--initial-branch=main"], at: url)
    try runGit(["config", "user.name", "Fixture Author"], at: url)
    try runGit(["config", "user.email", "fixture@example.invalid"], at: url)
    try Data("initial\n".utf8).write(to: url.appendingPathComponent("README.md"))
    try runGit(["add", "README.md"], at: url)
    try runGit(["commit", "--quiet", "--no-gpg-sign", "-m", "Initial fixture"], at: url)
    return try runGit(["rev-parse", "HEAD"], at: url)
}

func repositoryRoot(path: String, aliases: [String] = ["demo"]) -> RepositoryRoot {
    RepositoryRoot(
        id: UUID(),
        displayName: "DemoRepo",
        rootPath: path,
        aliases: aliases,
        environmentLabel: "test"
    )
}

func knowledgeRoot(
    path: String,
    includes: [String] = ["**/*.md", "**/*.txt"],
    excludes: [String] = []
) -> KnowledgeRoot {
    KnowledgeRoot(
        id: UUID(),
        displayName: "DemoWiki",
        rootPath: path,
        kind: .llmWiki,
        includePatterns: includes,
        excludePatterns: excludes
    )
}

enum TestSupportError: Error {
    case commandFailed(String)
}
