import CryptoKit
import Foundation
import MeetingInsightDomain

public struct KnowledgeDocument: Equatable, Sendable {
    public let relativePath: String
    public let content: String
    public let contentDigest: String
    public let modifiedAt: Date?

    public init(relativePath: String, content: String, contentDigest: String, modifiedAt: Date?) {
        self.relativePath = relativePath
        self.content = content
        self.contentDigest = contentDigest
        self.modifiedAt = modifiedAt
    }
}

public struct LocalKnowledgeProvider: Sendable {
    private static let defaultIncludePatterns = [
        "**/*.md",
        "**/*.mdx",
        "**/*.txt",
        "**/ADR-*",
        "**/adr/**",
    ]
    private static let defaultExcludePatterns = [
        ".git",
        ".git/**",
        "**/.git/**",
        ".env",
        ".env*",
        "**/.env",
        "**/.env*",
        ".build/**",
        "**/.build/**",
        ".swiftpm/**",
        "**/.swiftpm/**",
        ".artifacts/**",
        "**/.artifacts/**",
        "build/**",
        "**/build/**",
        "DerivedData/**",
        "**/DerivedData/**",
        "node_modules/**",
        "**/node_modules/**",
        "**/*.pem",
        "**/*.key",
        "**/*.p12",
        "**/*.pfx",
        "**/*.der",
        "id_rsa",
        "**/id_rsa",
        "id_ed25519",
        "**/id_ed25519",
        "credentials*",
        "**/credentials*",
        "secret*",
        "**/secret*",
    ]
    private static let maximumFileSize = 1_048_576

    public init() {}

    public func documents(in root: KnowledgeRoot) throws -> [KnowledgeDocument] {
        let canonicalRoot = try validateRoot(root)
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            throw RepositoryError.pathNotReadable(root.rootPath)
        }

        var documents: [KnowledgeDocument] = []
        for case let candidate as URL in enumerator {
            let values = try candidate.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isContained(resolved, in: canonicalRoot) else {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let relativePath = relativePath(of: resolved, from: canonicalRoot)
            if values.isDirectory == true, isExcluded(relativePath, root: root) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            guard isAllowed(relativePath, root: root) else { continue }
            guard (values.fileSize ?? 0) <= Self.maximumFileSize else { continue }

            let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
            guard let content = String(data: data, encoding: .utf8) else { continue }
            documents.append(
                KnowledgeDocument(
                    relativePath: relativePath,
                    content: content,
                    contentDigest: SHA256.hash(data: data).hexString,
                    modifiedAt: values.contentModificationDate
                )
            )
        }
        return documents.sorted { $0.relativePath < $1.relativePath }
    }

    public func read(relativePath: String, in root: KnowledgeRoot) throws -> KnowledgeDocument {
        let canonicalRoot = try validateRoot(root)
        try validateRelativePath(relativePath)
        guard isAllowed(relativePath, root: root) else {
            throw RepositoryError.pathNotAllowed(relativePath)
        }
        let candidate = canonicalRoot.appendingPathComponent(relativePath)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(resolved, in: canonicalRoot) else {
            throw RepositoryError.pathOutsideRoot(relativePath)
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw RepositoryError.pathDoesNotExist(relativePath)
        }
        let values = try candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true else {
            throw RepositoryError.pathDoesNotExist(relativePath)
        }
        guard (values.fileSize ?? 0) <= Self.maximumFileSize else {
            throw RepositoryError.invalidContent(relativePath)
        }
        let data = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        guard let content = String(data: data, encoding: .utf8) else {
            throw RepositoryError.invalidContent(relativePath)
        }
        return KnowledgeDocument(
            relativePath: relativePath,
            content: content,
            contentDigest: SHA256.hash(data: data).hexString,
            modifiedAt: values.contentModificationDate
        )
    }

    public func search(
        _ query: String,
        in root: KnowledgeRoot,
        limit: Int = 20
    ) throws -> [KnowledgeDocument] {
        guard limit > 0 else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return try documents(in: root)
            .filter { $0.content.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .prefix(limit)
            .map { $0 }
    }

    public func snapshot(
        _ root: KnowledgeRoot,
        capturedAt: Date = Date()
    ) throws -> KnowledgeSnapshot {
        let documents = try documents(in: root)
        var digest = SHA256()
        for document in documents {
            digest.update(data: Data(document.relativePath.utf8))
            digest.update(data: Data([0]))
            digest.update(data: Data(document.content.utf8))
            digest.update(data: Data([0]))
        }
        let canonicalURL = try validateRoot(root)
        let canonicalRoot = KnowledgeRoot(
            id: root.id,
            displayName: root.displayName,
            rootPath: canonicalURL.path,
            kind: root.kind,
            includePatterns: root.includePatterns,
            excludePatterns: root.excludePatterns
        )
        return KnowledgeSnapshot(
            root: canonicalRoot,
            revision: digest.finalize().hexString,
            fileCount: documents.count,
            capturedAt: capturedAt
        )
    }

    private func validateRoot(_ root: KnowledgeRoot) throws -> URL {
        let originalURL = URL(fileURLWithPath: root.rootPath, isDirectory: true)
        let canonicalURL = originalURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory) else {
            throw RepositoryError.pathDoesNotExist(root.rootPath)
        }
        guard isDirectory.boolValue else {
            throw RepositoryError.pathNotDirectory(root.rootPath)
        }
        guard FileManager.default.isReadableFile(atPath: canonicalURL.path) else {
            throw RepositoryError.pathNotReadable(root.rootPath)
        }
        return canonicalURL
    }

    private func validateRelativePath(_ relativePath: String) throws {
        let path = NSString(string: relativePath)
        guard !path.isAbsolutePath,
              !relativePath.isEmpty,
              !path.pathComponents.contains(".."),
              !path.pathComponents.contains(".")
        else {
            throw RepositoryError.invalidRelativePath(relativePath)
        }
    }

    private func relativePath(of candidate: URL, from root: URL) -> String {
        candidate.pathComponents
            .dropFirst(root.pathComponents.count)
            .joined(separator: "/")
    }

    private func isContained(_ candidate: URL, in root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func isAllowed(_ relativePath: String, root: KnowledgeRoot) -> Bool {
        let includes = root.includePatterns.isEmpty ? Self.defaultIncludePatterns : root.includePatterns
        return includes.contains { GlobPattern($0).matches(relativePath) }
            && !isExcluded(relativePath, root: root)
    }

    private func isExcluded(_ relativePath: String, root: KnowledgeRoot) -> Bool {
        (Self.defaultExcludePatterns + root.excludePatterns)
            .contains { GlobPattern($0).matches(relativePath) }
    }
}

private struct GlobPattern {
    private let expression: NSRegularExpression?

    init(_ pattern: String) {
        var result = "^"
        let characters = Array(pattern)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    if index + 2 < characters.count, characters[index + 2] == "/" {
                        result += "(?:.*/)?"
                        index += 3
                    } else {
                        result += ".*"
                        index += 2
                    }
                } else {
                    result += "[^/]*"
                    index += 1
                }
            } else if character == "?" {
                result += "[^/]"
                index += 1
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }
        result += "$"
        expression = try? NSRegularExpression(pattern: result, options: [.caseInsensitive])
    }

    func matches(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression?.firstMatch(in: value, range: range) != nil
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
