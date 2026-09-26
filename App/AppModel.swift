import Foundation
import MeetingInsightCapture
import MeetingInsightOrchestration
import Observation

enum AppSessionState: String, Equatable {
    case idle = "Idle"
    case investigating = "Investigating"
}

enum CaptureUIState: String, Equatable {
    case idle = "Capture idle"
    case loading = "Loading apps…"
    case starting = "Starting capture…"
    case capturing = "Capturing"
    case stopping = "Stopping capture…"
}

@MainActor
@Observable
final class AppModel {
    private let service: any MeetingInsightAppServicing
    private let captureService: any AudioCaptureServicing
    private var investigationTask: Task<Void, Never>?
    private var captureEventsTask: Task<Void, Never>?
    private var hasStartedLoading = false

    var sessionState: AppSessionState = .idle
    var scopes: [AppScopeSummary] = []
    var activeScopeID: UUID?
    var hasAcknowledgedPrivacy = false
    var question = ""
    var insight: AppInsightPresentation?
    var doctorReport: AppDoctorPresentation?
    var errorMessage: String?
    var activeRequestID: UUID?

    var captureState: CaptureUIState = .idle
    var captureApplications: [CaptureApplication] = []
    var selectedCaptureApplicationID: CaptureApplication.ID?
    var applicationAudioMeter = PCMMeterLevel.silence
    var microphoneMeter = PCMMeterLevel.silence
    var captureMetrics: CaptureStabilityReport?
    var captureErrorMessage: String?

    var draftScopeName = ""
    var draftRepositories: [RepositoryDraft] = []
    var draftKnowledge: [KnowledgeDraft] = []
    var isSavingScope = false
    var isRunningDoctor = false

    var activeScope: AppScopeSummary? {
        guard let activeScopeID else { return nil }
        return scopes.first { $0.id == activeScopeID }
    }

    init(
        service: any MeetingInsightAppServicing,
        captureService: any AudioCaptureServicing = AudioCaptureService()
    ) {
        self.service = service
        self.captureService = captureService
    }

    func load() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        Task { [weak self, service] in
            do {
                let bootstrap = try await service.bootstrap()
                guard let self else { return }
                apply(bootstrap)
            } catch {
                self?.errorMessage = "設定を読み込めませんでした。"
            }
        }
    }

    func acknowledgePrivacy() {
        Task { [weak self, service] in
            do {
                try await service.acknowledgePrivacy()
                self?.hasAcknowledgedPrivacy = true
            } catch {
                self?.errorMessage = "プライバシー確認を保存できませんでした。"
            }
        }
    }

    func selectActiveScope(_ id: UUID?) {
        let previous = activeScopeID
        activeScopeID = id
        Task { [weak self, service] in
            do {
                try await service.selectActiveScope(id)
            } catch {
                guard let self else { return }
                activeScopeID = previous
                errorMessage = "Active scopeを保存できませんでした。"
            }
        }
    }

    func addRepository(_ url: URL) {
        guard draftRepositories.count < 3 else { return }
        let name = url.lastPathComponent.isEmpty ? "Repository" : url.lastPathComponent
        draftRepositories.append(
            RepositoryDraft(displayName: name, rootPath: url.path, aliases: [name])
        )
    }

    func addKnowledge(_ url: URL) {
        guard draftKnowledge.count < 3 else { return }
        let name = url.lastPathComponent.isEmpty ? "Knowledge" : url.lastPathComponent
        draftKnowledge.append(KnowledgeDraft(displayName: name, rootPath: url.path))
    }

    func removeRepository(id: UUID) {
        draftRepositories.removeAll { $0.id == id }
    }

    func removeKnowledge(id: UUID) {
        draftKnowledge.removeAll { $0.id == id }
    }

    func saveScope() {
        guard !isSavingScope else { return }
        let draft = ResearchScopeDraft(
            name: draftScopeName,
            repositories: draftRepositories,
            knowledge: draftKnowledge
        )
        isSavingScope = true
        errorMessage = nil
        Task { [weak self, service] in
            do {
                let bootstrap = try await service.saveScope(draft)
                guard let self else { return }
                apply(bootstrap)
                draftScopeName = ""
                draftRepositories = []
                draftKnowledge = []
                isSavingScope = false
            } catch {
                guard let self else { return }
                isSavingScope = false
                errorMessage = "Research Scopeを保存できませんでした。"
            }
        }
    }

    func runDoctor() {
        guard !isRunningDoctor else { return }
        isRunningDoctor = true
        Task { [weak self, service] in
            let report = await service.doctor()
            guard let self else { return }
            doctorReport = report
            isRunningDoctor = false
        }
    }

    func investigate() {
        guard sessionState == .idle, let activeScopeID else { return }
        guard hasAcknowledgedPrivacy else {
            errorMessage = "調査前にデータ送信範囲を確認してください。"
            return
        }
        let submittedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuestion.isEmpty else { return }

        let requestID = UUID()
        activeRequestID = requestID
        sessionState = .investigating
        insight = nil
        errorMessage = nil
        investigationTask = Task { [weak self, service] in
            do {
                let result = try await service.investigate(
                    scopeID: activeScopeID,
                    question: submittedQuestion,
                    requestID: requestID
                )
                guard let self, activeRequestID == requestID else { return }
                insight = result
                activeRequestID = nil
                sessionState = .idle
            } catch is CancellationError {
                guard let self, activeRequestID == requestID else { return }
                activeRequestID = nil
                sessionState = .idle
            } catch {
                guard let self, activeRequestID == requestID else { return }
                activeRequestID = nil
                sessionState = .idle
                errorMessage = "調査を完了できませんでした。"
            }
        }
    }

    func cancelInvestigation() {
        guard let requestID = activeRequestID else { return }
        activeRequestID = nil
        sessionState = .idle
        investigationTask?.cancel()
        investigationTask = nil
        Task { [service] in
            await service.cancel(requestID: requestID)
        }
    }

    func refreshCaptureApplications() {
        guard captureState == .idle else { return }
        captureState = .loading
        captureErrorMessage = nil
        Task { [weak self, captureService] in
            do {
                let applications = try await captureService.applications()
                guard let self else { return }
                captureApplications = applications
                if !applications.contains(where: { $0.id == selectedCaptureApplicationID }) {
                    selectedCaptureApplicationID = applications.first(where: {
                        $0.applicationName.localizedCaseInsensitiveContains("zoom")
                    })?.id
                }
                captureState = .idle
            } catch {
                guard let self else { return }
                captureState = .idle
                captureErrorMessage = "共有可能なアプリを取得できませんでした。Screen Recording権限を確認してください。"
            }
        }
    }

    func startAudioCapture() {
        guard captureState == .idle, let applicationID = selectedCaptureApplicationID else { return }
        guard hasAcknowledgedPrivacy else {
            captureErrorMessage = "収音前にデータ境界を確認してください。"
            return
        }
        captureState = .starting
        captureErrorMessage = nil
        applicationAudioMeter = .silence
        microphoneMeter = .silence
        captureMetrics = nil
        captureEventsTask = Task { [weak self, captureService] in
            do {
                let events = try await captureService.start(applicationID: applicationID)
                guard let self, captureEventsTask?.isCancelled == false else {
                    await captureService.stop()
                    return
                }
                captureState = .capturing
                for await event in events {
                    guard !Task.isCancelled else { return }
                    consume(event)
                }
                if captureState != .idle {
                    captureState = .idle
                }
            } catch is CancellationError {
                self?.captureState = .idle
            } catch {
                guard let self else { return }
                captureState = .idle
                captureErrorMessage = "音声captureを開始できませんでした。権限と選択アプリを確認してください。"
            }
        }
    }

    func stopAudioCapture() {
        guard captureState != .idle, captureState != .loading else { return }
        captureState = .stopping
        let task = captureEventsTask
        Task { [weak self, captureService] in
            await captureService.stop()
            task?.cancel()
            guard let self else { return }
            captureEventsTask = nil
            applicationAudioMeter = .silence
            microphoneMeter = .silence
            captureState = .idle
        }
    }

    private func consume(_ event: CaptureEvent) {
        switch event {
        case .meter(let sample):
            switch sample.source {
            case .applicationAudio: applicationAudioMeter = sample.level
            case .microphone: microphoneMeter = sample.level
            }
        case .metrics(let report):
            captureMetrics = report
        case .failed:
            captureErrorMessage = "capture streamが停止しました。権限または選択アプリを確認してください。"
            captureState = .idle
            Task { [captureService] in await captureService.stop() }
        case .stopped:
            captureState = .idle
        }
    }

    private func apply(_ bootstrap: AppBootstrap) {
        scopes = bootstrap.scopes
        activeScopeID = bootstrap.activeScopeID
        hasAcknowledgedPrivacy = bootstrap.hasAcknowledgedPrivacy
    }
}
