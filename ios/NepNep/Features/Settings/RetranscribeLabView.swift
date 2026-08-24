import AVFoundation
import SwiftData
import SwiftUI

/// 설정 > 전사 실험실 (#21 후속, 개발용)
///
/// 남아 있는 m4a를 파이프라인 입력 포맷으로 되돌려 다시 전사해 보는 자리다.
/// 전사기를 손볼 때 결과가 어떻게 달라지는지, 신뢰도가 실제로 실려 오는지를
/// 회의를 새로 녹음하지 않고 확인할 수 있다.
struct RetranscribeLabView: View {
    @Query(filter: #Predicate<Meeting> { $0.audioSize > 0 },
           sort: \Meeting.createdAt, order: .reverse)
    private var meetings: [Meeting]

    @State private var lab = RetranscribeLab()

    var body: some View {
        List {
            formatSection
            meetingSection

            if let error = lab.errorText {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let pass = lab.pass {
                statsSection(pass)
                textSection(pass)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.background)
        .navigationTitle("전사 실험실")
        .navigationBarTitleDisplayMode(.inline)
        .task { await lab.loadFormat() }
    }

    // MARK: - 오디오 포맷

    private var formatSection: some View {
        Section {
            row("녹음 캡처", "\(Int(ChunkedAudioWriter.sampleRate / 1000))kHz mono Int16")
            row("전사기 선호", lab.preferredFormat)
        } header: {
            Text("오디오 포맷")
        } footer: {
            Text("둘이 다르면 녹음 시점에 정보를 버리고 있다는 뜻입니다. 캡처는 되돌릴 수 없습니다.")
        }
    }

    // MARK: - 회의 고르기

    private var meetingSection: some View {
        Section {
            if meetings.isEmpty {
                Text("오디오가 남아 있는 회의가 없습니다.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(meetings) { meeting in
                Button {
                    lab.run(meetingID: meeting.id, title: meeting.title)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Text(MeetingDateFormat.relative(meeting.createdAt))
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        Spacer()
                        Text(StorageCalc.byteText(meeting.audioSize))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .disabled(lab.isRunning)
            }
        } header: {
            Text("재전사할 회의")
        } footer: {
            if lab.isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(lab.progressText)
                        .foregroundStyle(DesignTokens.accent)
                }
            } else {
                Text("녹음 길이만큼 걸립니다. 결과는 화면에만 보여주고 회의에는 반영하지 않습니다.")
            }
        }
    }

    // MARK: - 결과

    private func statsSection(_ pass: TranscriptionPass) -> some View {
        Section {
            row("전사한 곳", lab.engineName, tint: DesignTokens.textPrimary)
            row("단어 수", "\(pass.wordCount)")
            row("평균 신뢰도", pct(pass.averageConfidence))
            row("최저 신뢰도", pct(pass.minimumConfidence))
            row("신뢰도 매겨진 비율", pct(pass.scoredRatio))
        } header: {
            Text("집계 — \(lab.title)")
        } footer: {
            // 신뢰도 속성이 실제로 붙어 오는지 확인하는 자리다
            Text(pass.scoredRatio == 0
                 ? "신뢰도가 전부 1입니다 — transcriptionConfidence가 안 붙어 오고 있습니다."
                 : "신뢰도가 실려 오고 있습니다.")
                .foregroundStyle(pass.scoredRatio == 0 ? .red : DesignTokens.textSecondary)
        }
    }

    private func textSection(_ pass: TranscriptionPass) -> some View {
        Section("전문") {
            transcript(pass.text)
        }
    }

    private func transcript(_ text: String) -> some View {
        Text(text.isEmpty ? "(빈 결과)" : text)
            .font(.footnote)
            .foregroundStyle(DesignTokens.textPrimary)
            .textSelection(.enabled)
            .padding(.vertical, 4)
    }

    // MARK: - 조각

    private func row(_ label: String, _ value: String,
                     tint: Color = DesignTokens.textSecondary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Text(value)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

/// 실험 실행 상태 — 진행률 콜백이 뷰 밖에서 들어오므로 별도 모델로 뺀다
@MainActor
@Observable
final class RetranscribeLab {
    private(set) var pass: TranscriptionPass?
    private(set) var errorText: String?
    private(set) var isRunning = false
    private(set) var progressText = ""
    private(set) var title = ""
    private(set) var preferredFormat = "확인 중…"
    /// 이번 판을 실제로 무엇이 돌렸는지 — 서버로 갔는지 기기 안으로 떨어졌는지
    private(set) var engineName = ""

    func loadFormat() async {
        guard let format = await SpeechTranscriberEngine.preferredAudioFormat() else {
            preferredFormat = "알 수 없음"
            return
        }
        preferredFormat = "\(Int(format.sampleRate / 1000))kHz "
            + "\(format.channelCount)ch \(format.commonFormat.label)"
    }

    func run(meetingID: UUID, title: String) {
        guard !isRunning else { return }
        self.title = title
        pass = nil
        errorText = nil
        engineName = ""
        isRunning = true
        progressText = "엔진 확인 중…"

        Task {
            defer { isRunning = false }
            do {
                // 설정에서 고른 엔진으로 돌린다 — 실험실이 기기 안 전사만 쓰면
                // 서버를 붙여 놓고도 결과를 비교할 수가 없다.
                let choice = await EngineCatalog.shared.makeEngine()
                engineName = EngineCatalog.shared.selected.name
                    + (choice.usedFallback ? " → 기기 안 (서버에 못 붙음)" : "")

                let input = try prepareInput(meetingID: meetingID, engine: choice.engine)
                defer { if input.isTemporary { try? FileManager.default.removeItem(at: input.url) } }

                let reportsProgress = choice.engine.reportsProgress
                progressText = reportsProgress ? "전사 중… 0%" : "올리는 중… 0%"
                let words = try await choice.engine.transcribe(url: input.url) { fraction in
                    Task { @MainActor [weak self] in
                        self?.progressText = Self.progressLabel(fraction,
                                                                reportsProgress: reportsProgress)
                    }
                }
                pass = TranscriptionPass(words: words)
                progressText = ""
            } catch {
                let code = (error as NSError).code
                errorText = error.localizedDescription + " (\(code))"
                progressText = ""
            }
        }
    }

    /// 원격 엔진은 다 올린 뒤부터 서버가 도는 동안을 알 길이 없다.
    /// 절반에서 멈춘 퍼센트를 보여주느니 그때부터는 숫자를 걷는다.
    static func progressLabel(_ fraction: Double, reportsProgress: Bool) -> String {
        if reportsProgress { return "전사 중… \(Int(fraction * 100))%" }
        return fraction < 1 ? "올리는 중… \(Int(fraction * 100))%" : "서버에서 전사 중…"
    }

    /// 기기 안 전사기는 파이프라인 포맷(CAF)을 받으므로 m4a를 되돌려 준다.
    /// 원격 엔진은 어차피 m4a로 압축해 올리므로 원본을 그대로 넘긴다 —
    /// 굳이 되돌렸다가 다시 압축하면 AAC를 두 번 먹여 비교가 불공정해진다.
    private func prepareInput(meetingID: UUID,
                              engine: any TranscriptionEngine) throws -> (url: URL, isTemporary: Bool) {
        let m4a = AudioFileStore.m4aURL(meetingID: meetingID)
        guard FileManager.default.fileExists(atPath: m4a.path) else {
            throw NSError(domain: "RetranscribeLab", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "이 회의의 오디오 파일이 없습니다.",
            ])
        }
        if engine is RemoteTranscriptionEngine { return (m4a, false) }

        progressText = "오디오 되돌리는 중…"
        let caf = FileManager.default.temporaryDirectory
            .appendingPathComponent("retranscribe-\(meetingID.uuidString).caf")
        try AudioTranscoder.decodeToPipelineCAF(source: m4a, to: caf)
        return (caf, true)
    }
}

private extension AVAudioCommonFormat {
    var label: String {
        switch self {
        case .pcmFormatInt16: return "Int16"
        case .pcmFormatInt32: return "Int32"
        case .pcmFormatFloat32: return "Float32"
        case .pcmFormatFloat64: return "Float64"
        case .otherFormat: return "기타"
        @unknown default: return "알 수 없음"
        }
    }
}
