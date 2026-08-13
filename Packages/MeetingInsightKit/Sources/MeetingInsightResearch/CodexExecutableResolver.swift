import Foundation

public enum CodexExecutableResolverError: Error, Equatable, Sendable {
    case invalidExplicitPath(String)
    case notFound
}

public struct CodexExecutableResolver: Sendable {
    private let environmentPath: String
    private let knownLocations: [URL]
    private let homeDirectory: URL

    public init(
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        knownLocations: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environmentPath = environmentPath
        self.homeDirectory = homeDirectory
        self.knownLocations = knownLocations ?? [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
        ]
    }

    public func resolve(explicitPath: String?) throws -> URL {
        if let explicitPath {
            guard explicitPath.hasPrefix("/"), let url = validated(URL(fileURLWithPath: explicitPath)) else {
                throw CodexExecutableResolverError.invalidExplicitPath(explicitPath)
            }
            return url
        }

        let pathCandidates = environmentPath
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        for candidate in pathCandidates + knownLocations {
            if let url = validated(candidate) { return url }
        }
        throw CodexExecutableResolverError.notFound
    }

    private func validated(_ candidate: URL) -> URL? {
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.isFileURL, resolved.path.hasPrefix("/") else { return nil }
        guard
            let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
            values.isRegularFile == true,
            FileManager.default.isExecutableFile(atPath: resolved.path)
        else {
            return nil
        }
        return resolved
    }
}
