import Foundation

public struct CaptureApplication: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = Int32

    public var id: ID { processID }
    public let processID: Int32
    public let bundleIdentifier: String
    public let applicationName: String

    public init(processID: Int32, bundleIdentifier: String, applicationName: String) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
    }
}

public enum CaptureOutputKind: String, Codable, Equatable, Sendable {
    case applicationAudio
    case microphone
}

public struct AudioCapturePlan: Codable, Equatable, Sendable {
    public let outputKinds: [CaptureOutputKind]
    public let capturesApplicationAudio: Bool
    public let capturesMicrophone: Bool
    public let excludesCurrentProcessAudio: Bool
    public let channelCount: Int
    public let sampleRate: Int?
    public let targetDuration: TimeInterval

    public init(
        outputKinds: [CaptureOutputKind],
        capturesApplicationAudio: Bool,
        capturesMicrophone: Bool,
        excludesCurrentProcessAudio: Bool,
        channelCount: Int,
        sampleRate: Int?,
        targetDuration: TimeInterval
    ) {
        self.outputKinds = outputKinds
        self.capturesApplicationAudio = capturesApplicationAudio
        self.capturesMicrophone = capturesMicrophone
        self.excludesCurrentProcessAudio = excludesCurrentProcessAudio
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.targetDuration = targetDuration
    }

    public static let gateA = AudioCapturePlan(
        outputKinds: [.applicationAudio, .microphone],
        capturesApplicationAudio: true,
        capturesMicrophone: true,
        excludesCurrentProcessAudio: true,
        channelCount: 1,
        sampleRate: nil,
        targetDuration: 30 * 60
    )

    public static let gateAMemoryGrowthBudgetBytes: UInt64 = 50 * 1_048_576
}

public struct PCMMeterLevel: Codable, Equatable, Sendable {
    public let peak: Float
    public let rootMeanSquare: Float

    public init(peak: Float, rootMeanSquare: Float) {
        self.peak = peak
        self.rootMeanSquare = rootMeanSquare
    }

    public static let silence = PCMMeterLevel(peak: 0, rootMeanSquare: 0)
}

public struct CaptureMeterSample: Codable, Equatable, Sendable {
    public let source: CaptureOutputKind
    public let level: PCMMeterLevel
    public let presentationTime: TimeInterval
    public let frameCount: Int

    public init(
        source: CaptureOutputKind,
        level: PCMMeterLevel,
        presentationTime: TimeInterval,
        frameCount: Int
    ) {
        self.source = source
        self.level = level
        self.presentationTime = presentationTime
        self.frameCount = frameCount
    }
}

public enum CaptureMemoryTrend: String, Codable, Equatable, Sendable {
    case insufficientData
    case stableOrMixed
    case monotonicIncrease
}

public struct CaptureTimestampRange: Codable, Equatable, Sendable {
    public let first: TimeInterval
    public let last: TimeInterval
    public let isMonotonic: Bool

    public var duration: TimeInterval {
        max(0, last - first)
    }

    public init(first: TimeInterval, last: TimeInterval, isMonotonic: Bool) {
        self.first = first
        self.last = last
        self.isMonotonic = isMonotonic
    }
}

public struct CaptureStabilityReport: Codable, Equatable, Sendable {
    public let duration: TimeInterval
    public let applicationAudioFrameCount: Int
    public let microphoneFrameCount: Int
    public let minimumResidentBytes: UInt64?
    public let maximumResidentBytes: UInt64?
    public let initialResidentBytes: UInt64?
    public let finalResidentBytes: UInt64?
    public let memoryTrend: CaptureMemoryTrend
    public let applicationAudioTimestampRange: CaptureTimestampRange?
    public let microphoneTimestampRange: CaptureTimestampRange?

    public var presentationTimestampOverlap: TimeInterval? {
        guard let applicationAudioTimestampRange,
              let microphoneTimestampRange,
              applicationAudioTimestampRange.isMonotonic,
              microphoneTimestampRange.isMonotonic
        else {
            return nil
        }
        let start = max(applicationAudioTimestampRange.first, microphoneTimestampRange.first)
        let end = min(applicationAudioTimestampRange.last, microphoneTimestampRange.last)
        return max(0, end - start)
    }

    public var timestampsAreMixable: Bool {
        presentationTimestampOverlap.map { $0 > 0 } ?? false
    }

    public var residentGrowthBytes: UInt64? {
        guard let initialResidentBytes, let finalResidentBytes else { return nil }
        return finalResidentBytes > initialResidentBytes
            ? finalResidentBytes - initialResidentBytes
            : 0
    }

    public var isWithinGateAMemoryGrowthBudget: Bool {
        residentGrowthBytes.map { $0 < AudioCapturePlan.gateAMemoryGrowthBudgetBytes } ?? false
    }

    public var meetsGateA: Bool {
        duration >= AudioCapturePlan.gateA.targetDuration
            && applicationAudioFrameCount > 0
            && microphoneFrameCount > 0
            && memoryTrend == .stableOrMixed
            && isWithinGateAMemoryGrowthBudget
            && timestampsAreMixable
    }

    public init(
        duration: TimeInterval,
        applicationAudioFrameCount: Int,
        microphoneFrameCount: Int,
        minimumResidentBytes: UInt64?,
        maximumResidentBytes: UInt64?,
        initialResidentBytes: UInt64?,
        finalResidentBytes: UInt64?,
        memoryTrend: CaptureMemoryTrend,
        applicationAudioTimestampRange: CaptureTimestampRange?,
        microphoneTimestampRange: CaptureTimestampRange?
    ) {
        self.duration = duration
        self.applicationAudioFrameCount = applicationAudioFrameCount
        self.microphoneFrameCount = microphoneFrameCount
        self.minimumResidentBytes = minimumResidentBytes
        self.maximumResidentBytes = maximumResidentBytes
        self.initialResidentBytes = initialResidentBytes
        self.finalResidentBytes = finalResidentBytes
        self.memoryTrend = memoryTrend
        self.applicationAudioTimestampRange = applicationAudioTimestampRange
        self.microphoneTimestampRange = microphoneTimestampRange
    }
}

public struct CaptureStabilityAccumulator: Sendable {
    private let startedAt: TimeInterval
    private var applicationAudioFrameCount = 0
    private var microphoneFrameCount = 0
    private var residentBytes: [UInt64] = []
    private var applicationAudioTimestamps = TimestampAccumulator()
    private var microphoneTimestamps = TimestampAccumulator()

    public init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    public mutating func record(
        source: CaptureOutputKind,
        frameCount: Int,
        presentationTime: TimeInterval
    ) {
        switch source {
        case .applicationAudio:
            applicationAudioFrameCount = max(applicationAudioFrameCount, frameCount)
            applicationAudioTimestamps.record(presentationTime)
        case .microphone:
            microphoneFrameCount = max(microphoneFrameCount, frameCount)
            microphoneTimestamps.record(presentationTime)
        }
    }

    public mutating func recordResidentBytes(_ bytes: UInt64, at _: TimeInterval) {
        residentBytes.append(bytes)
    }

    public func report(endedAt: TimeInterval) -> CaptureStabilityReport {
        let trend: CaptureMemoryTrend
        if residentBytes.count < 3 {
            trend = .insufficientData
        } else {
            let pairs = zip(residentBytes, residentBytes.dropFirst())
            trend = pairs.allSatisfy { previous, current in current > previous }
                ? .monotonicIncrease
                : .stableOrMixed
        }
        return CaptureStabilityReport(
            duration: max(0, endedAt - startedAt),
            applicationAudioFrameCount: applicationAudioFrameCount,
            microphoneFrameCount: microphoneFrameCount,
            minimumResidentBytes: residentBytes.min(),
            maximumResidentBytes: residentBytes.max(),
            initialResidentBytes: residentBytes.first,
            finalResidentBytes: residentBytes.last,
            memoryTrend: trend,
            applicationAudioTimestampRange: applicationAudioTimestamps.range,
            microphoneTimestampRange: microphoneTimestamps.range
        )
    }
}

private struct TimestampAccumulator: Sendable {
    private var first: TimeInterval?
    private var last: TimeInterval?
    private var isMonotonic = true

    mutating func record(_ value: TimeInterval) {
        guard value.isFinite else { return }
        if let last, value < last {
            isMonotonic = false
        }
        first = first ?? value
        last = value
    }

    var range: CaptureTimestampRange? {
        guard let first, let last else { return nil }
        return CaptureTimestampRange(first: first, last: last, isMonotonic: isMonotonic)
    }
}

public enum CaptureEvent: Equatable, Sendable {
    case meter(CaptureMeterSample)
    case metrics(CaptureStabilityReport)
    case failed(CaptureFailure)
    case stopped
}

public struct CaptureFailure: Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

public enum AudioCaptureError: Error, Equatable, Sendable {
    case alreadyRunning
    case applicationNotFound
    case displayNotFound
}

public protocol AudioCaptureBackendSession: Sendable {
    var events: AsyncStream<CaptureEvent> { get }
    func stop() async
}

public protocol AudioCaptureBackend: Sendable {
    func applications() async throws -> [CaptureApplication]
    func start(
        applicationID: CaptureApplication.ID,
        plan: AudioCapturePlan
    ) async throws -> any AudioCaptureBackendSession
}

public protocol AudioCaptureServicing: Sendable {
    var isCapturing: Bool { get async }
    func applications() async throws -> [CaptureApplication]
    func start(applicationID: CaptureApplication.ID) async throws -> AsyncStream<CaptureEvent>
    func stop() async
}
