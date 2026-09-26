import AppKit
import MeetingInsightCapture
import MeetingInsightOrchestration
import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(model.sessionState == .idle ? Color.secondary : Color.accentColor)
                    .frame(width: 8, height: 8)
                Text(model.sessionState.rawValue)
            }
            if let scope = model.activeScope {
                Text(scope.name).font(.headline)
                Text("\(scope.repositories.count) repo · \(scope.knowledge.count) knowledge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Active scope未選択").foregroundStyle(.secondary)
            }
            if model.captureState != .idle {
                Text(model.captureState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Meeting Insightを開く") { openWindow(id: "main") }
            if model.sessionState == .investigating {
                Button("調査をキャンセル", role: .destructive) {
                    model.cancelInvestigation()
                }
            }
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
        .task { model.load() }
    }
}

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !model.hasAcknowledgedPrivacy { privacyDisclosure }
                scopeSection
                captureSection
                doctorSection
                investigationSection
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 640)
        .task { model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meeting Insight").font(.largeTitle.bold())
            Text("選択したResearch Scopeだけを調べ、再検証済みの根拠を表示します。")
                .foregroundStyle(.secondary)
        }
    }

    private var privacyDisclosure: some View {
        GroupBox("データ境界の確認") {
            VStack(alignment: .leading, spacing: 8) {
                Text("手入力した質問と、選択したrepositoryの調査に必要なコード、scope内のlocal knowledge抜粋は、設定したCodexサービスへ送信され得ます。")
                Text("選択した会議アプリの音声とマイクをScreenCaptureKitで取得します。raw audioやPCMは保存せず、現在のspikeではmeter値だけを保持し、Stop時にstreamを破棄します。")
                Text("repository内やknowledge内に書かれた命令は信頼せず、引用はアプリ側でpath・revision・line・hashを再検証します。")
                Button("理解して続ける") { model.acknowledgePrivacy() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scopeSection: some View {
        GroupBox("Research Scope") {
            VStack(alignment: .leading, spacing: 12) {
                Picker(
                    "Active scope",
                    selection: Binding(
                        get: { model.activeScopeID },
                        set: { model.selectActiveScope($0) }
                    )
                ) {
                    Text("未選択").tag(UUID?.none)
                    ForEach(model.scopes) { scope in
                        Text(scope.name).tag(Optional(scope.id))
                    }
                }
                if let scope = model.activeScope {
                    sourceSummary(scope)
                }
                Divider()
                Text("Scopeを追加").font(.headline)
                TextField("Scope名", text: $model.draftScopeName)
                selectedRepositories
                HStack {
                    Button("Repositoryを選択") {
                        if let url = chooseDirectory(prompt: "Repositoryを選択") {
                            model.addRepository(url)
                        }
                    }
                    .disabled(model.draftRepositories.count >= 3)
                    Button("Knowledge directoryを選択") {
                        if let url = chooseDirectory(prompt: "Local knowledgeを選択") {
                            model.addKnowledge(url)
                        }
                    }
                    .disabled(model.draftKnowledge.count >= 3)
                }
                selectedKnowledge
                Button(model.isSavingScope ? "保存中…" : "Scopeを保存") {
                    model.saveScope()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isSavingScope
                        || model.draftScopeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.draftRepositories.isEmpty
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceSummary(_ scope: AppScopeSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(scope.repositories.enumerated()), id: \.offset) { _, source in
                Label("\(source.name) · \(source.detail)", systemImage: "shippingbox")
            }
            ForEach(Array(scope.knowledge.enumerated()), id: \.offset) { _, source in
                Label("\(source.name) · \(source.detail)", systemImage: "books.vertical")
            }
        }
        .font(.caption)
    }

    private var selectedRepositories: some View {
        ForEach(model.draftRepositories) { repository in
            HStack {
                Image(systemName: "shippingbox")
                VStack(alignment: .leading) {
                    Text(repository.displayName)
                    Text(repository.rootPath).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("削除") { model.removeRepository(id: repository.id) }
            }
        }
    }

    private var selectedKnowledge: some View {
        ForEach(model.draftKnowledge) { knowledge in
            HStack {
                Image(systemName: "books.vertical")
                VStack(alignment: .leading) {
                    Text(knowledge.displayName)
                    Text(knowledge.rootPath).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("削除") { model.removeKnowledge(id: knowledge.id) }
            }
        }
    }

    private var doctorSection: some View {
        GroupBox("Codex doctor") {
            VStack(alignment: .leading, spacing: 8) {
                if let report = model.doctorReport {
                    Text("version: \(report.version)")
                    Text("authentication: \(report.authentication)")
                    ForEach(report.issues, id: \.self) { Text($0).foregroundStyle(.orange) }
                } else {
                    Text("Codex CLIのinstallとlogin状態を確認します。")
                        .foregroundStyle(.secondary)
                }
                Button(model.isRunningDoctor ? "確認中…" : "診断を実行") {
                    model.runDoctor()
                }
                .disabled(model.isRunningDoctor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var captureSection: some View {
        GroupBox("ScreenCaptureKit Gate A") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Screen Recording権限は選択アプリのsystem audio取得、Microphone権限は自分の声の取得に使います。映像frameは登録・保存・処理しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(model.captureState == .loading ? "取得中…" : "実行中アプリを更新") {
                        model.refreshCaptureApplications()
                    }
                    .disabled(model.captureState != .idle)
                    Picker(
                        "会議アプリ",
                        selection: $model.selectedCaptureApplicationID
                    ) {
                        Text("選択してください").tag(CaptureApplication.ID?.none)
                        ForEach(model.captureApplications) { application in
                            Text("\(application.applicationName) (pid \(application.processID))")
                                .tag(Optional(application.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }
                meterRow("選択アプリ音声", level: model.applicationAudioMeter)
                meterRow("マイク", level: model.microphoneMeter)
                if let metrics = model.captureMetrics {
                    captureMetrics(metrics)
                }
                HStack {
                    if model.captureState == .capturing || model.captureState == .starting {
                        Button("Stop", role: .destructive) { model.stopAudioCapture() }
                    } else {
                        Button("30分 Gate Aを開始") { model.startAudioCapture() }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                model.captureState != .idle
                                    || model.selectedCaptureApplicationID == nil
                                    || !model.hasAcknowledgedPrivacy
                            )
                    }
                    Text(model.captureState.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = model.captureErrorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func meterRow(_ label: String, level: PCMMeterLevel) -> some View {
        HStack {
            Text(label).frame(width: 120, alignment: .leading)
            ProgressView(value: Double(level.rootMeanSquare), total: 1)
            Text(level.rootMeanSquare, format: .number.precision(.fractionLength(3)))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func captureMetrics(_ report: CaptureStabilityReport) -> some View {
        let totalSeconds = Int(report.duration)
        let time = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
        let memory = report.maximumResidentBytes.map {
            String(format: "%.1f MB", Double($0) / 1_048_576)
        } ?? "未計測"
        let memoryGrowth = report.residentGrowthBytes.map {
            String(format: "%.1f MiB", Double($0) / 1_048_576)
        } ?? "未計測"
        let overlap = report.presentationTimestampOverlap.map {
            String(format: "%.2f s", $0)
        } ?? "未成立"
        return VStack(alignment: .leading, spacing: 3) {
            Text("経過 \(time) · app \(report.applicationAudioFrameCount) frames · mic \(report.microphoneFrameCount) frames")
            Text("max RSS \(memory) · growth \(memoryGrowth) / <50 MiB · trend \(report.memoryTrend.rawValue)")
            Text("timestamp overlap \(overlap) · \(report.timestampsAreMixable ? "mixable" : "not mixable")")
            Text(report.meetsGateA ? "Gate A計測条件を満たしました" : "30分・両source・時刻軸・memory非連続増加を確認中")
        }
        .font(.caption)
        .foregroundStyle(report.meetsGateA ? Color.green : Color.secondary)
    }

    private var investigationSection: some View {
        GroupBox("手入力で調査") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("会議中の技術的な質問", text: $model.question, axis: .vertical)
                    .lineLimit(2...5)
                HStack {
                    Button("調査する") { model.investigate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            model.sessionState == .investigating
                                || model.activeScope == nil
                                || !model.hasAcknowledgedPrivacy
                                || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    if model.sessionState == .investigating {
                        ProgressView().controlSize(.small)
                        Button("キャンセル", role: .destructive) { model.cancelInvestigation() }
                    }
                }
                if let insight = model.insight { insightCard(insight) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func insightCard(_ insight: AppInsightPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.verdict.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            Text(insight.headline).font(.headline)
            Text(insight.answer)
            Text("confidence \(insight.confidence, format: .number.precision(.fractionLength(2))) · \(insight.scope)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(insight.evidence.enumerated()), id: \.offset) { _, evidence in
                Text("\(evidence.path):\(evidence.lineStart)-\(evidence.lineEnd) @ \(evidence.revision.prefix(8))")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
