import Foundation

public enum RepositoryError: Error, Equatable, Sendable {
    case pathDoesNotExist(String)
    case pathNotDirectory(String)
    case pathNotReadable(String)
    case pathOutsideRoot(String)
    case pathNotAllowed(String)
    case invalidRelativePath(String)
    case invalidContent(String)
    case notGitRepository(String)
    case repositoryRootMismatch(expected: String, actual: String)
    case invalidGitOutput(String)
    case commandFailed(exitCode: Int32, standardError: String)
    case commandTimedOut(executable: String, timeout: Duration)
    case commandOutputLimitExceeded(Int)
    case invalidScope(String)
}
