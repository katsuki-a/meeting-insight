import Foundation

public struct CommandInvocation: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let currentDirectory: URL
    public let timeout: Duration
    public let outputLimit: Int

    public init(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        timeout: Duration,
        outputLimit: Int
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.timeout = timeout
        self.outputLimit = outputLimit
    }
}

public struct CommandOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CommandExecuting: Sendable {
    func run(_ invocation: CommandInvocation) async throws -> CommandOutput
}

public struct FoundationCommandExecutor: CommandExecuting {
    public init() {}

    public func run(_ invocation: CommandInvocation) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            ProcessExecution(invocation: invocation, continuation: continuation).start()
        }
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let invocation: CommandInvocation
    private let continuation: CheckedContinuation<CommandOutput, Error>
    private let process = Process()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let lock = NSLock()
    private var outputData = Data()
    private var errorData = Data()
    private var terminalError: Error?
    private var exitCode: Int32?
    private var outputReachedEnd = false
    private var errorReachedEnd = false
    private var completed = false
    private var keepAlive: ProcessExecution?

    init(
        invocation: CommandInvocation,
        continuation: CheckedContinuation<CommandOutput, Error>
    ) {
        self.invocation = invocation
        self.continuation = continuation
    }

    func start() {
        keepAlive = self
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            self?.recordTermination(exitCode: process.terminationStatus)
        }
        standardOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStandardError: false)
        }
        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStandardError: true)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            try? standardOutput.fileHandleForWriting.close()
            try? standardError.fileHandleForWriting.close()
            completeImmediately(with: .failure(error))
            return
        }
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()

        let timeout = invocation.timeout
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + timeout.timeInterval
        ) { [weak self] in
            guard let self else { return }
            lock.lock()
            let shouldTerminate = !completed && process.isRunning
            if shouldTerminate {
                terminalError = RepositoryError.commandTimedOut(
                    executable: invocation.executable.path,
                    timeout: timeout
                )
            }
            lock.unlock()
            if shouldTerminate {
                process.terminate()
            }
        }
    }

    private func consume(_ data: Data, isStandardError: Bool) {
        var completion: Result<CommandOutput, Error>?
        var shouldTerminate = false
        lock.lock()
        if data.isEmpty {
            if isStandardError {
                errorReachedEnd = true
            } else {
                outputReachedEnd = true
            }
        } else if terminalError == nil {
            if outputData.count + errorData.count + data.count > invocation.outputLimit {
                terminalError = RepositoryError.commandOutputLimitExceeded(invocation.outputLimit)
                shouldTerminate = process.isRunning
            } else if isStandardError {
                errorData.append(data)
            } else {
                outputData.append(data)
            }
        }
        completion = takeCompletionIfReady()
        lock.unlock()

        if data.isEmpty {
            if isStandardError {
                standardError.fileHandleForReading.readabilityHandler = nil
            } else {
                standardOutput.fileHandleForReading.readabilityHandler = nil
            }
        }
        if shouldTerminate {
            process.terminate()
        }
        resume(completion)
    }

    private func recordTermination(exitCode: Int32) {
        var completion: Result<CommandOutput, Error>?
        lock.lock()
        self.exitCode = exitCode
        completion = takeCompletionIfReady()
        lock.unlock()
        resume(completion)
    }

    private func takeCompletionIfReady() -> Result<CommandOutput, Error>? {
        guard !completed,
              let exitCode,
              outputReachedEnd,
              errorReachedEnd
        else {
            return nil
        }
        completed = true
        keepAlive = nil
        if let terminalError {
            return .failure(terminalError)
        }
        return .success(
            CommandOutput(
                exitCode: exitCode,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            )
        )
    }

    private func completeImmediately(with result: Result<CommandOutput, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        keepAlive = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    private func resume(_ result: Result<CommandOutput, Error>?) {
        if let result {
            continuation.resume(with: result)
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
