public actor AudioCaptureService: AudioCaptureServicing {
    private let backend: any AudioCaptureBackend
    private var session: (any AudioCaptureBackendSession)?

    public private(set) var isCapturing = false

    public init(backend: any AudioCaptureBackend) {
        self.backend = backend
    }

    public init() {
        backend = ScreenCaptureKitAudioBackend()
    }

    public func applications() async throws -> [CaptureApplication] {
        try await backend.applications()
    }

    public func start(
        applicationID: CaptureApplication.ID
    ) async throws -> AsyncStream<CaptureEvent> {
        guard session == nil else { throw AudioCaptureError.alreadyRunning }
        let started = try await backend.start(applicationID: applicationID, plan: .gateA)
        session = started
        isCapturing = true
        return started.events
    }

    public func stop() async {
        guard let running = session else { return }
        session = nil
        isCapturing = false
        await running.stop()
    }
}
