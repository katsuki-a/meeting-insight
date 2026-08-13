import Darwin
import Foundation
import MeetingInsightDomain

public struct CodexProcessLimits: Equatable, Sendable {
    public let stdoutBytes: Int
    public let stderrBytes: Int
    public let lineBytes: Int
    public let softTimeout: Duration
    public let hardTimeout: Duration
    public let killGrace: Duration

    public init(
        stdoutBytes: Int = 10 * 1_048_576,
        stderrBytes: Int = 2 * 1_048_576,
        lineBytes: Int = 1_048_576,
        softTimeout: Duration = .seconds(35),
        hardTimeout: Duration = .seconds(90),
        killGrace: Duration = .seconds(2)
    ) {
        self.stdoutBytes = stdoutBytes
        self.stderrBytes = stderrBytes
        self.lineBytes = lineBytes
        self.softTimeout = softTimeout
        self.hardTimeout = hardTimeout
        self.killGrace = killGrace
    }
}

public struct CodexRunRequest: Sendable {
    public let requestID: UUID
    public let executableURL: URL
    public let repositoryURL: URL
    public let schemaURL: URL
    public let prompt: String

    public init(
        requestID: UUID,
        executableURL: URL,
        repositoryURL: URL,
        schemaURL: URL,
        prompt: String
    ) {
        self.requestID = requestID
        self.executableURL = executableURL
        self.repositoryURL = repositoryURL
        self.schemaURL = schemaURL
        self.prompt = prompt
    }
}

public struct CodexRunMetrics: Equatable, Sendable {
    public let exitCode: Int32
    public let terminationSignal: Int32?
    public let durationMilliseconds: Int
    public let eventCount: Int
    public let usage: CodexTokenUsage?
    public let exceededSoftTimeout: Bool

    public init(
        exitCode: Int32,
        terminationSignal: Int32? = nil,
        durationMilliseconds: Int,
        eventCount: Int,
        usage: CodexTokenUsage?,
        exceededSoftTimeout: Bool
    ) {
        self.exitCode = exitCode
        self.terminationSignal = terminationSignal
        self.durationMilliseconds = durationMilliseconds
        self.eventCount = eventCount
        self.usage = usage
        self.exceededSoftTimeout = exceededSoftTimeout
    }
}

public struct CodexRunResult: Equatable, Sendable {
    public let card: AgentInsightCard
    public let metrics: CodexRunMetrics

    public init(card: AgentInsightCard, metrics: CodexRunMetrics) {
        self.card = card
        self.metrics = metrics
    }
}

public enum CodexRunnerError: Error, Equatable, Sendable {
    case duplicateRequestID
    case processLaunchFailed
    case promptWriteFailed
    case malformedJSONL
    case nonZeroExit(Int32)
    case stdoutLimitExceeded
    case stderrLimitExceeded
    case lineLimitExceeded
    case sourcePolicyViolation(CodexSourcePolicyViolation)
    case hardTimeout
    case cancelled
    case missingFinalMessage
    case invalidFinalMessage
    case agentReportedFailure
}

public actor CodexProcessRunner {
    private let limits: CodexProcessLimits
    private let environmentOverrides: [String: String]
    private var executions: [UUID: CodexProcessExecution] = [:]

    public init(
        limits: CodexProcessLimits = CodexProcessLimits(),
        environmentOverrides: [String: String] = [:]
    ) {
        self.limits = limits
        self.environmentOverrides = environmentOverrides
    }

    public func run(_ request: CodexRunRequest) async throws -> CodexRunResult {
        guard executions[request.requestID] == nil else {
            throw CodexRunnerError.duplicateRequestID
        }
        let execution = CodexProcessExecution(
            request: request,
            limits: limits,
            environment: Self.processEnvironment(overrides: environmentOverrides)
        )
        executions[request.requestID] = execution
        defer { executions.removeValue(forKey: request.requestID) }
        return try await withTaskCancellationHandler {
            try await execution.run()
        } onCancel: {
            execution.cancel()
        }
    }

    public func cancel(requestID: UUID) {
        executions[requestID]?.cancel()
    }

    private static func processEnvironment(overrides: [String: String]) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        let allowedKeys = [
            "HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG", "LC_ALL", "CODEX_HOME",
            "SSL_CERT_FILE", "SSL_CERT_DIR",
        ]
        var environment = Dictionary(uniqueKeysWithValues: allowedKeys.compactMap { key in
            inherited[key].map { (key, $0) }
        })
        environment.merge(overrides) { _, override in override }
        return environment
    }
}

private final class CodexProcessExecution: @unchecked Sendable {
    private let request: CodexRunRequest
    private let limits: CodexProcessLimits
    private let environment: [String: String]
    private let process = Process()
    private let standardInput = Pipe()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let decoder = CodexEventDecoder()
    private let sourcePolicy = CodexSourcePolicy()
    private let lock = NSLock()

    private var continuation: CheckedContinuation<CodexRunResult, Error>?
    private var keepAlive: CodexProcessExecution?
    private var stdoutBuffer = Data()
    private var stdoutCount = 0
    private var stderrCount = 0
    private var eventCount = 0
    private var usage: CodexTokenUsage?
    private var finalMessage: String?
    private var terminalError: CodexRunnerError?
    private var exitCode: Int32?
    private var terminationSignal: Int32?
    private var stdoutReachedEnd = false
    private var stderrReachedEnd = false
    private var exceededSoftTimeout = false
    private var completed = false
    private var terminationRequested = false
    private var startTime = ContinuousClock.now

    init(request: CodexRunRequest, limits: CodexProcessLimits, environment: [String: String]) {
        self.request = request
        self.limits = limits
        self.environment = environment
    }

    func run() async throws -> CodexRunResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
                keepAlive = self
            }
            start()
        }
    }

    func cancel() {
        failAndTerminate(.cancelled)
    }

    private func start() {
        let command = CodexCommandBuilder().command(
            executableURL: request.executableURL,
            repositoryURL: request.repositoryURL,
            schemaURL: request.schemaURL
        )
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = request.repositoryURL
        process.environment = environment
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            self?.recordTermination(
                exitCode: process.terminationStatus,
                wasUncaughtSignal: process.terminationReason == .uncaughtSignal
            )
        }
        standardOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeStandardOutput(handle.availableData)
        }
        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeStandardError(handle.availableData)
        }

        do {
            startTime = .now
            try process.run()
        } catch {
            cleanupAfterLaunchFailure()
            finishImmediately(.failure(CodexRunnerError.processLaunchFailed))
            return
        }
        try? standardInput.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()

        do {
            try standardInput.fileHandleForWriting.write(contentsOf: Data(request.prompt.utf8))
            try standardInput.fileHandleForWriting.close()
        } catch {
            failAndTerminate(.promptWriteFailed)
        }

        scheduleTimeouts()
    }

    private func scheduleTimeouts() {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + limits.softTimeout.timeInterval
        ) { [weak self] in
            self?.markSoftTimeout()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + limits.hardTimeout.timeInterval
        ) { [weak self] in
            self?.failAndTerminate(.hardTimeout)
        }
    }

    private func markSoftTimeout() {
        lock.withLock {
            if !completed { exceededSoftTimeout = true }
        }
    }

    private func consumeStandardOutput(_ data: Data) {
        if data.isEmpty {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            var error: CodexRunnerError?
            lock.withLock {
                if !stdoutBuffer.isEmpty, terminalError == nil {
                    error = decodeLineLocked(stdoutBuffer)
                    stdoutBuffer.removeAll(keepingCapacity: false)
                }
                stdoutReachedEnd = true
            }
            if let error { failAndTerminate(error) }
            completeIfReady()
            return
        }

        var error: CodexRunnerError?
        lock.withLock {
            guard terminalError == nil, !completed else { return }
            stdoutCount += data.count
            guard stdoutCount <= limits.stdoutBytes else {
                error = .stdoutLimitExceeded
                return
            }
            stdoutBuffer.append(data)
            while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = Data(stdoutBuffer[..<newline])
                stdoutBuffer.removeSubrange(...newline)
                if line.count > limits.lineBytes {
                    error = .lineLimitExceeded
                    break
                }
                if !line.isEmpty, let lineError = decodeLineLocked(line) {
                    error = lineError
                    break
                }
            }
            if error == nil, stdoutBuffer.count > limits.lineBytes {
                error = .lineLimitExceeded
            }
        }
        if let error { failAndTerminate(error) }
    }

    private func consumeStandardError(_ data: Data) {
        if data.isEmpty {
            standardError.fileHandleForReading.readabilityHandler = nil
            lock.withLock { stderrReachedEnd = true }
            completeIfReady()
            return
        }
        var exceeded = false
        lock.withLock {
            guard terminalError == nil, !completed else { return }
            stderrCount += data.count
            exceeded = stderrCount > limits.stderrBytes
        }
        if exceeded { failAndTerminate(.stderrLimitExceeded) }
    }

    private func decodeLineLocked(_ line: Data) -> CodexRunnerError? {
        let event: CodexEvent
        do {
            event = try decoder.decode(line)
        } catch {
            return .malformedJSONL
        }
        eventCount += 1
        if let violation = sourcePolicy.violation(for: event) {
            return .sourcePolicyViolation(violation)
        }
        if case .itemCompleted(let item) = event,
           item.kind == .agentMessage,
           let text = item.text
        {
            finalMessage = text
        }
        if case .turnCompleted(let tokenUsage) = event {
            usage = tokenUsage
        }
        if case .turnFailed = event { return .agentReportedFailure }
        if case .error = event { return .agentReportedFailure }
        return nil
    }

    private func recordTermination(exitCode: Int32, wasUncaughtSignal: Bool) {
        lock.withLock {
            self.exitCode = exitCode
            terminationSignal = wasUncaughtSignal ? exitCode : nil
        }
        completeIfReady()
    }

    private func failAndTerminate(_ error: CodexRunnerError) {
        var shouldTerminate = false
        lock.withLock {
            guard !completed else { return }
            if terminalError == nil { terminalError = error }
            guard !terminationRequested, process.isRunning else { return }
            terminationRequested = true
            shouldTerminate = true
        }
        guard shouldTerminate else {
            completeIfReady()
            return
        }
        process.terminate()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + limits.killGrace.timeInterval
        ) { [weak self] in
            self?.forceKillIfNeeded()
        }
    }

    private func forceKillIfNeeded() {
        let pid: pid_t? = lock.withLock {
            guard !completed, process.isRunning else { return nil }
            return process.processIdentifier
        }
        if let pid { Darwin.kill(pid, SIGKILL) }
    }

    private func completeIfReady() {
        let completion: (CheckedContinuation<CodexRunResult, Error>, Result<CodexRunResult, Error>)? = lock.withLock {
            guard
                !completed,
                let continuation,
                let exitCode,
                stdoutReachedEnd,
                stderrReachedEnd
            else {
                return nil
            }
            completed = true
            self.continuation = nil
            let result: Result<CodexRunResult, Error>
            if let terminalError {
                result = .failure(terminalError)
            } else if exitCode != 0 {
                result = .failure(CodexRunnerError.nonZeroExit(exitCode))
            } else if let finalMessage {
                do {
                    let card = try InsightCardCoding.decoder().decode(
                        AgentInsightCard.self,
                        from: Data(finalMessage.utf8)
                    )
                    guard card.requestID == request.requestID else {
                        result = .failure(CodexRunnerError.invalidFinalMessage)
                        keepAlive = nil
                        return (continuation, result)
                    }
                    let duration = startTime.duration(to: .now)
                    result = .success(
                        CodexRunResult(
                            card: card,
                            metrics: CodexRunMetrics(
                                exitCode: exitCode,
                                terminationSignal: terminationSignal,
                                durationMilliseconds: duration.milliseconds,
                                eventCount: eventCount,
                                usage: usage,
                                exceededSoftTimeout: exceededSoftTimeout
                            )
                        )
                    )
                } catch {
                    result = .failure(CodexRunnerError.invalidFinalMessage)
                }
            } else {
                result = .failure(CodexRunnerError.missingFinalMessage)
            }
            keepAlive = nil
            return (continuation, result)
        }
        if let (continuation, result) = completion {
            continuation.resume(with: result)
        }
    }

    private func cleanupAfterLaunchFailure() {
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        try? standardInput.fileHandleForWriting.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
    }

    private func finishImmediately(_ result: Result<CodexRunResult, Error>) {
        let continuation: CheckedContinuation<CodexRunResult, Error>? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            let continuation = self.continuation
            self.continuation = nil
            keepAlive = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    var milliseconds: Int {
        let components = self.components
        let seconds = components.seconds * 1_000
        let fractional = components.attoseconds / 1_000_000_000_000_000
        return Int(seconds + fractional)
    }
}
