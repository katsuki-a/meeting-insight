import Foundation

public struct CodexCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public struct CodexCommandBuilder: Sendable {
    public init() {}

    public func command(
        executableURL: URL,
        repositoryURL: URL,
        schemaURL: URL
    ) -> CodexCommand {
        CodexCommand(
            executableURL: executableURL,
            arguments: [
                "exec",
                "--cd", repositoryURL.path,
                "--sandbox", "read-only",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--json",
                "--color", "never",
                "--output-schema", schemaURL.path,
                "-",
            ]
        )
    }
}
