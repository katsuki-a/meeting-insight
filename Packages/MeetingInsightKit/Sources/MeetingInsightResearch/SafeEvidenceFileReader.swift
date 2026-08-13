import Darwin
import Foundation

enum EvidenceFileReadError: Error, Equatable {
    case invalidPath
    case outsideRoot
    case unreadable
    case changedDuringValidation
}

protocol EvidenceFileReading: Sendable {
    func read(relativePath: String, rootURL: URL) throws -> Data
}

struct SafeEvidenceFileReader: EvidenceFileReading {
    private static let maximumFileSize: Int64 = 8 * 1_048_576
    private let beforeOpen: @Sendable () throws -> Void

    init(beforeOpen: @escaping @Sendable () throws -> Void = {}) {
        self.beforeOpen = beforeOpen
    }

    func read(relativePath: String, rootURL: URL) throws -> Data {
        try validate(relativePath: relativePath)
        let canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = canonicalRoot.appendingPathComponent(relativePath)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolved, in: canonicalRoot) else {
            throw EvidenceFileReadError.outsideRoot
        }
        var pathBeforeOpen = stat()
        guard lstat(resolved.path, &pathBeforeOpen) == 0,
              (pathBeforeOpen.st_mode & S_IFMT) == S_IFREG
        else {
            throw EvidenceFileReadError.unreadable
        }

        try beforeOpen()
        let descriptor = Darwin.open(
            resolved.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            let postOpenResolution = candidate.resolvingSymlinksInPath().standardizedFileURL
            if postOpenResolution != resolved {
                throw EvidenceFileReadError.changedDuringValidation
            }
            throw EvidenceFileReadError.unreadable
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size <= Self.maximumFileSize,
              sameFile(pathBeforeOpen, before)
        else {
            throw EvidenceFileReadError.changedDuringValidation
        }
        let data = try handle.readToEnd() ?? Data()
        var after = stat()
        guard fstat(descriptor, &after) == 0 else {
            throw EvidenceFileReadError.unreadable
        }
        let postReadResolution = candidate.resolvingSymlinksInPath().standardizedFileURL
        var pathAfterRead = stat()
        guard lstat(resolved.path, &pathAfterRead) == 0,
              sameFile(before, after),
              sameFile(after, pathAfterRead),
              postReadResolution == resolved
        else {
            throw EvidenceFileReadError.changedDuringValidation
        }
        return data
    }

    private func validate(relativePath: String) throws {
        let path = NSString(string: relativePath)
        guard !relativePath.isEmpty,
              !path.isAbsolutePath,
              !path.pathComponents.contains(".."),
              !path.pathComponents.contains(".")
        else {
            throw EvidenceFileReadError.invalidPath
        }
    }

    private func contains(_ candidate: URL, in root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func sameFile(_ before: stat, _ after: stat) -> Bool {
        before.st_dev == after.st_dev
            && before.st_ino == after.st_ino
            && before.st_size == after.st_size
            && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
            && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
    }
}
