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
                Text(lab.progressText)
                    .foregroundStyle(DesignTokens.accent)
            } else {
                Text("녹음 길이만큼 걸립니다. 결과는 화면에만 보여주고 회의에는 반영하지 않습니다.")
            }
        }
    }

    // MARK: - 결과

    private func statsSection(_ pass: TranscriptionPass) -> some View {
        Section {
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
        isRunning = true
        progressText = "오디오 되돌리는 중…"

        Task {
            defer { isRunning = false }
            do {
                let caf = try decodeToTemporaryCAF(meetingID: meetingID)
                defer { try? FileManager.default.removeItem(at: caf) }

                pass = TranscriptionPass(words: try await transcribe(caf))
                progressText = ""
            } catch {
                errorText = error.localizedDescription
                progressText = ""
            }
        }
    }

    private func decodeToTemporaryCAF(meetingID: UUID) throws -> URL {
        let m4a = AudioFileStore.m4aURL(meetingID: meetingID)
        guard FileManager.default.fileExists(atPath: m4a.path) else {
            throw NSError(domain: "RetranscribeLab", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "이 회의의 오디오 파일이 없습니다.",
            ])
        }
        let caf = FileManager.default.temporaryDirectory
            .appendingPathComponent("retranscribe-\(meetingID.uuidString).caf")
        try AudioTranscoder.decodeToPipelineCAF(source: m4a, to: caf)
        return caf
    }

    private func transcribe(_ url: URL) async throws -> [TranscriptWord] {
        progressText = "전사 중… 0%"
        return try await SpeechTranscriberEngine().transcribe(url: url) { fraction in
            Task { @MainActor [weak self] in
                self?.progressText = "전사 중… \(Int(fraction * 100))%"
            }
        }
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
