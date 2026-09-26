import AVFAudio
import XCTest
@testable import MeetingInsightCapture

final class AudioCapturePlanTests: XCTestCase {
    func testGateAPlanRegistersAudioAndMicrophoneWithoutVideo() {
        let plan = AudioCapturePlan.gateA

        XCTAssertEqual(plan.outputKinds, [.applicationAudio, .microphone])
        XCTAssertTrue(plan.capturesApplicationAudio)
        XCTAssertTrue(plan.capturesMicrophone)
        XCTAssertTrue(plan.excludesCurrentProcessAudio)
        XCTAssertEqual(plan.channelCount, 1)
        XCTAssertNil(plan.sampleRate)
        XCTAssertEqual(plan.targetDuration, 1_800)
    }
}

final class PCMMeterTests: XCTestCase {
    func testMeasuresPeakAndRootMeanSquareWithoutRetainingPCM() {
        let level = PCMMeter.measure([0, 0.5, -0.5, 1])

        XCTAssertEqual(level.peak, 1, accuracy: 0.000_001)
        XCTAssertEqual(level.rootMeanSquare, 0.612_372, accuracy: 0.000_001)
    }

    func testEmptyOrNonFiniteSamplesProduceSilence() {
        XCTAssertEqual(PCMMeter.measure([]), .silence)
        XCTAssertEqual(PCMMeter.measure([.nan, .infinity]), .silence)
    }

    func testMeasuresInterleavedStereoNativeMicrophoneFormat() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo))
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                interleaved: true,
                channelLayout: layout
            )
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let samples = try XCTUnwrap(audioBuffers[0].mData?.assumingMemoryBound(to: Float.self))
        [Float(0.25), -0.25, 0.5, -0.5].enumerated().forEach { index, value in
            samples[index] = value
        }

        let level = try XCTUnwrap(PCMBufferMeter.measure(buffer))

        XCTAssertEqual(level.peak, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(level.rootMeanSquare, 0.395_285, accuracy: 0.000_001)
    }
}

final class CaptureStabilityAccumulatorTests: XCTestCase {
    func testThirtyMinuteRunWithBothSourcesAndPlateauingMemoryPassesGate() throws {
        var accumulator = CaptureStabilityAccumulator(startedAt: 100)
        accumulator.record(source: .applicationAudio, frameCount: 480, presentationTime: 100)
        accumulator.record(source: .microphone, frameCount: 480, presentationTime: 100.02)
        accumulator.record(source: .applicationAudio, frameCount: 9_000, presentationTime: 1_900)
        accumulator.record(source: .microphone, frameCount: 8_900, presentationTime: 1_900.02)
        accumulator.recordResidentBytes(100, at: 100)
        accumulator.recordResidentBytes(110, at: 700)
        accumulator.recordResidentBytes(108, at: 1_300)
        accumulator.recordResidentBytes(109, at: 1_900)

        let report = accumulator.report(endedAt: 1_900)

        XCTAssertEqual(report.duration, 1_800)
        XCTAssertEqual(report.memoryTrend, .stableOrMixed)
        XCTAssertTrue(report.isWithinGateAMemoryGrowthBudget)
        let overlap = try XCTUnwrap(report.presentationTimestampOverlap)
        XCTAssertEqual(overlap, 1_799.98, accuracy: 0.000_001)
        XCTAssertTrue(report.timestampsAreMixable)
        XCTAssertTrue(report.meetsGateA)
    }

    func testContinuouslyIncreasingMemoryFailsGate() {
        var accumulator = CaptureStabilityAccumulator(startedAt: 0)
        accumulator.record(source: .applicationAudio, frameCount: 1, presentationTime: 0)
        accumulator.record(source: .microphone, frameCount: 1, presentationTime: 0)
        accumulator.record(source: .applicationAudio, frameCount: 2, presentationTime: 1_800)
        accumulator.record(source: .microphone, frameCount: 2, presentationTime: 1_800)
        accumulator.recordResidentBytes(100, at: 0)
        accumulator.recordResidentBytes(110, at: 600)
        accumulator.recordResidentBytes(120, at: 1_200)
        accumulator.recordResidentBytes(130, at: 1_800)

        let report = accumulator.report(endedAt: 1_800)

        XCTAssertEqual(report.memoryTrend, .monotonicIncrease)
        XCTAssertFalse(report.meetsGateA)
    }

    func testFiftyMiBResidentGrowthFailsGateEvenWhenTrendIsMixed() {
        let mebibyte = UInt64(1_048_576)
        var accumulator = CaptureStabilityAccumulator(startedAt: 0)
        accumulator.record(source: .applicationAudio, frameCount: 1, presentationTime: 0)
        accumulator.record(source: .microphone, frameCount: 1, presentationTime: 0)
        accumulator.record(source: .applicationAudio, frameCount: 2, presentationTime: 1_800)
        accumulator.record(source: .microphone, frameCount: 2, presentationTime: 1_800)
        accumulator.recordResidentBytes(100 * mebibyte, at: 0)
        accumulator.recordResidentBytes(130 * mebibyte, at: 600)
        accumulator.recordResidentBytes(120 * mebibyte, at: 1_200)
        accumulator.recordResidentBytes(150 * mebibyte, at: 1_800)

        let report = accumulator.report(endedAt: 1_800)

        XCTAssertEqual(report.memoryTrend, .stableOrMixed)
        XCTAssertEqual(report.residentGrowthBytes, 50 * mebibyte)
        XCTAssertFalse(report.isWithinGateAMemoryGrowthBudget)
        XCTAssertFalse(report.meetsGateA)
    }

    func testDisjointPresentationTimelinesFailMixabilityGate() {
        var accumulator = CaptureStabilityAccumulator(startedAt: 0)
        accumulator.record(source: .applicationAudio, frameCount: 1, presentationTime: 0)
        accumulator.record(source: .applicationAudio, frameCount: 2, presentationTime: 10)
        accumulator.record(source: .microphone, frameCount: 1, presentationTime: 20)
        accumulator.record(source: .microphone, frameCount: 2, presentationTime: 30)
        accumulator.recordResidentBytes(100, at: 0)
        accumulator.recordResidentBytes(100, at: 900)
        accumulator.recordResidentBytes(100, at: 1_800)

        let report = accumulator.report(endedAt: 1_800)

        XCTAssertEqual(report.presentationTimestampOverlap, 0)
        XCTAssertFalse(report.timestampsAreMixable)
        XCTAssertFalse(report.meetsGateA)
    }

    func testRegressingPresentationTimelineFailsMixabilityGate() {
        var accumulator = CaptureStabilityAccumulator(startedAt: 0)
        accumulator.record(source: .applicationAudio, frameCount: 1, presentationTime: 10)
        accumulator.record(source: .applicationAudio, frameCount: 2, presentationTime: 5)
        accumulator.record(source: .microphone, frameCount: 1, presentationTime: 0)
        accumulator.record(source: .microphone, frameCount: 2, presentationTime: 20)

        let report = accumulator.report(endedAt: 20)

        XCTAssertFalse(report.applicationAudioTimestampRange?.isMonotonic ?? true)
        XCTAssertNil(report.presentationTimestampOverlap)
        XCTAssertFalse(report.timestampsAreMixable)
    }
}

final class AudioCaptureServiceTests: XCTestCase {
    func testStopReleasesRunningBackendSession() async throws {
        let session = FakeCaptureSession()
        let backend = FakeCaptureBackend(session: session)
        let service = AudioCaptureService(backend: backend)
        let application = CaptureApplication(
            processID: 42,
            bundleIdentifier: "synthetic.zoom",
            applicationName: "Synthetic Meeting"
        )

        _ = try await service.start(applicationID: application.id)
        var isCapturing = await service.isCapturing
        XCTAssertTrue(isCapturing)

        await service.stop()

        isCapturing = await service.isCapturing
        XCTAssertFalse(isCapturing)
        let stopCount = await session.stopCount
        XCTAssertEqual(stopCount, 1)
    }

    func testSecondStartIsRejectedWithoutLeakingFirstSession() async throws {
        let session = FakeCaptureSession()
        let service = AudioCaptureService(backend: FakeCaptureBackend(session: session))
        _ = try await service.start(applicationID: 42)

        do {
            _ = try await service.start(applicationID: 42)
            XCTFail("Expected an already-running failure")
        } catch {
            XCTAssertEqual(error as? AudioCaptureError, .alreadyRunning)
        }

        var stopCount = await session.stopCount
        XCTAssertEqual(stopCount, 0)
        await service.stop()
        stopCount = await session.stopCount
        XCTAssertEqual(stopCount, 1)
    }
}

private actor FakeCaptureBackend: AudioCaptureBackend {
    let session: FakeCaptureSession

    init(session: FakeCaptureSession) {
        self.session = session
    }

    func applications() async throws -> [CaptureApplication] { [] }

    func start(
        applicationID: CaptureApplication.ID,
        plan: AudioCapturePlan
    ) async throws -> any AudioCaptureBackendSession {
        XCTAssertEqual(applicationID, 42)
        XCTAssertEqual(plan, .gateA)
        return session
    }
}

private final class FakeCaptureSession: AudioCaptureBackendSession, @unchecked Sendable {
    let events: AsyncStream<CaptureEvent>
    private let state = State()

    init() {
        events = AsyncStream { _ in }
    }

    var stopCount: Int {
        get async { await state.stopCount }
    }

    func stop() async {
        await state.stop()
    }

    private actor State {
        private(set) var stopCount = 0

        func stop() {
            stopCount += 1
        }
    }
}
