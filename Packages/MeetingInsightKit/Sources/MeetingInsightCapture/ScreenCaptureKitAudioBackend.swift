@preconcurrency import AVFAudio
@preconcurrency import CoreMedia
import Darwin.Mach
import Foundation
@preconcurrency import ScreenCaptureKit

public struct ScreenCaptureKitAudioBackend: AudioCaptureBackend {
    public init() {}

    public func applications() async throws -> [CaptureApplication] {
        let content = try await shareableContent()
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        return content.applications
            .filter { $0.processID != currentProcessID }
            .map(Self.application)
            .sorted {
                let comparison = $0.applicationName.localizedStandardCompare($1.applicationName)
                return comparison == .orderedSame ? $0.processID < $1.processID : comparison == .orderedAscending
            }
    }

    public func start(
        applicationID: CaptureApplication.ID,
        plan: AudioCapturePlan
    ) async throws -> any AudioCaptureBackendSession {
        let content = try await shareableContent()
        guard let application = content.applications.first(where: { $0.processID == applicationID }) else {
            throw AudioCaptureError.applicationNotFound
        }
        guard let display = Self.preferredDisplay(
            for: application,
            windows: content.windows,
            displays: content.displays
        ) else {
            throw AudioCaptureError.displayNotFound
        }
        let filter = SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
        return try await ScreenCaptureKitAudioSession.start(filter: filter, plan: plan)
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
    }

    private static func application(_ value: SCRunningApplication) -> CaptureApplication {
        CaptureApplication(
            processID: value.processID,
            bundleIdentifier: value.bundleIdentifier,
            applicationName: value.applicationName
        )
    }

    private static func preferredDisplay(
        for application: SCRunningApplication,
        windows: [SCWindow],
        displays: [SCDisplay]
    ) -> SCDisplay? {
        let applicationFrames = windows.compactMap { window -> CGRect? in
            guard window.owningApplication?.processID == application.processID else { return nil }
            return window.frame
        }
        return displays.max { left, right in
            visibleArea(of: applicationFrames, on: left.frame)
                < visibleArea(of: applicationFrames, on: right.frame)
        }
    }

    private static func visibleArea(of frames: [CGRect], on display: CGRect) -> CGFloat {
        frames.reduce(into: 0) { area, frame in
            let intersection = frame.intersection(display)
            if !intersection.isNull {
                area += intersection.width * intersection.height
            }
        }
    }
}

private actor ScreenCaptureKitAudioSession: AudioCaptureBackendSession {
    nonisolated let events: AsyncStream<CaptureEvent>

    private let stream: SCStream
    private let output: CaptureStreamOutput
    private var memoryTask: Task<Void, Never>?
    private var isStopped = false

    private init(
        stream: SCStream,
        output: CaptureStreamOutput,
        events: AsyncStream<CaptureEvent>
    ) {
        self.stream = stream
        self.output = output
        self.events = events
    }

    static func start(
        filter: SCContentFilter,
        plan: AudioCapturePlan
    ) async throws -> ScreenCaptureKitAudioSession {
        let pair = AsyncStream<CaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let output = CaptureStreamOutput(continuation: pair.continuation)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = plan.capturesApplicationAudio
        configuration.captureMicrophone = plan.capturesMicrophone
        configuration.excludesCurrentProcessAudio = plan.excludesCurrentProcessAudio
        configuration.channelCount = plan.channelCount
        if let sampleRate = plan.sampleRate {
            configuration.sampleRate = sampleRate
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        let session = ScreenCaptureKitAudioSession(
            stream: stream,
            output: output,
            events: pair.stream
        )
        do {
            try stream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: output.applicationAudioQueue
            )
            try stream.addStreamOutput(
                output,
                type: .microphone,
                sampleHandlerQueue: output.microphoneQueue
            )
            try await stream.startCapture()
            await session.startMemorySampling()
            return session
        } catch {
            try? stream.removeStreamOutput(output, type: .audio)
            try? stream.removeStreamOutput(output, type: .microphone)
            output.finish()
            throw error
        }
    }

    func stop() async {
        guard !isStopped else { return }
        isStopped = true
        memoryTask?.cancel()
        memoryTask = nil
        output.beginStopping()
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(output, type: .audio)
        try? stream.removeStreamOutput(output, type: .microphone)
        output.finish()
    }

    private func startMemorySampling() {
        output.recordResidentBytes(ProcessResidentMemory.currentBytes())
        memoryTask = Task { [output] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                output.recordResidentBytes(ProcessResidentMemory.currentBytes())
            }
        }
    }
}

private final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let applicationAudioQueue = DispatchQueue(
        label: "dev.katsuki.MeetingInsight.capture.application-audio",
        qos: .userInitiated
    )
    let microphoneQueue = DispatchQueue(
        label: "dev.katsuki.MeetingInsight.capture.microphone",
        qos: .userInitiated
    )

    private let lock = NSLock()
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var accumulator: CaptureStabilityAccumulator
    private var applicationAudioFrameCount = 0
    private var microphoneFrameCount = 0
    private var lastYieldAt: [CaptureOutputKind: TimeInterval] = [:]
    private var isStopping = false
    private var isFinished = false

    init(continuation: AsyncStream<CaptureEvent>.Continuation) {
        self.continuation = continuation
        accumulator = CaptureStabilityAccumulator(startedAt: startedAt)
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        let source: CaptureOutputKind
        switch type {
        case .audio: source = .applicationAudio
        case .microphone: source = .microphone
        default: return
        }
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let frameCount = sampleBuffer.numSamples
        guard frameCount > 0, let level = PCMBufferMeter.measure(sampleBuffer) else { return }
        let presentationTime = sampleBuffer.presentationTimeStamp.seconds
        let now = ProcessInfo.processInfo.systemUptime
        let sample: CaptureMeterSample? = lock.withLock {
            switch source {
            case .applicationAudio: applicationAudioFrameCount += frameCount
            case .microphone: microphoneFrameCount += frameCount
            }
            let cumulative = source == .applicationAudio
                ? applicationAudioFrameCount
                : microphoneFrameCount
            accumulator.record(
                source: source,
                frameCount: cumulative,
                presentationTime: presentationTime
            )
            guard now - (lastYieldAt[source] ?? 0) >= 0.05 else { return nil }
            lastYieldAt[source] = now
            return CaptureMeterSample(
                source: source,
                level: level,
                presentationTime: presentationTime,
                frameCount: cumulative
            )
        }
        if let sample {
            continuation.yield(.meter(sample))
        }
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        let shouldReportFailure = lock.withLock { !isStopping }
        if shouldReportFailure {
            let nsError = error as NSError
            continuation.yield(
                .failed(CaptureFailure(domain: nsError.domain, code: nsError.code))
            )
        }
        finish()
    }

    func recordResidentBytes(_ bytes: UInt64?) {
        guard let bytes else { return }
        let report = lock.withLock { () -> CaptureStabilityReport in
            let now = ProcessInfo.processInfo.systemUptime
            accumulator.recordResidentBytes(bytes, at: now)
            return accumulator.report(endedAt: now)
        }
        continuation.yield(.metrics(report))
    }

    func beginStopping() {
        lock.withLock { isStopping = true }
    }

    func finish() {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        guard shouldFinish else { return }
        continuation.yield(.stopped)
        continuation.finish()
    }
}

enum PCMBufferMeter {
    static func measure(_ sampleBuffer: CMSampleBuffer) -> PCMMeterLevel? {
        guard let description = sampleBuffer.formatDescription else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            return nil
        }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return measure(buffer)
    }

    static func measure(_ buffer: AVAudioPCMBuffer) -> PCMMeterLevel? {
        guard buffer.frameLength > 0 else { return nil }
        var peak: Float = 0
        var sumOfSquares: Double = 0
        var sampleCount = 0
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            for audioBuffer in audioBuffers {
                guard let data = audioBuffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                for index in 0..<count {
                    let sample = samples[index]
                    guard sample.isFinite else { continue }
                    peak = max(peak, abs(sample))
                    sumOfSquares += Double(sample) * Double(sample)
                    sampleCount += 1
                }
            }
        case .pcmFormatInt16:
            for audioBuffer in audioBuffers {
                guard let data = audioBuffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Int16.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size
                for index in 0..<count {
                    let sample = Float(samples[index]) / Float(Int16.max)
                    peak = max(peak, abs(sample))
                    sumOfSquares += Double(sample) * Double(sample)
                    sampleCount += 1
                }
            }
        case .pcmFormatInt32:
            for audioBuffer in audioBuffers {
                guard let data = audioBuffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Int32.self)
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int32>.size
                for index in 0..<count {
                    let sample = Float(samples[index]) / Float(Int32.max)
                    peak = max(peak, abs(sample))
                    sumOfSquares += Double(sample) * Double(sample)
                    sampleCount += 1
                }
            }
        default:
            return nil
        }
        guard sampleCount > 0 else { return nil }
        return PCMMeterLevel(
            peak: min(peak, 1),
            rootMeanSquare: Float((sumOfSquares / Double(sampleCount)).squareRoot())
        )
    }
}

private enum ProcessResidentMemory {
    static func currentBytes() -> UInt64? {
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(information.resident_size)
    }
}
