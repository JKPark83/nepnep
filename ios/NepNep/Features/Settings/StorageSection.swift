import SwiftData
import SwiftUI

/// 설정 > 저장 공간 (08-m5 §4, 와이어프레임 1h)
///
/// 보관량 상한이 없으므로(PRD F11-1) 막대는 "할당량 대비 사용률"이 아니라
/// 오디오·텍스트 **구성비**다 — 항상 가득 찬 2색 막대로 그려 소진 게이지로 오해되지 않게 한다.
struct StorageSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Meeting> { $0.audioSize > 0 },
           sort: \Meeting.audioSize, order: .reverse)
    private var audioMeetings: [Meeting]
    @State private var audioBytes: Int64 = 0
    @State private var dataBytes: Int64 = 0
    @State private var showDeleteConfirm = false

    private var dataColor: Color { DesignTokens.accent.opacity(0.28) }

    var body: some View {
        Section("저장 공간") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("전체 사용량")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Text(StorageCalc.byteText(audioBytes + dataBytes))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                compositionBar
                HStack(spacing: 12) {
                    legend(DesignTokens.accent, "오디오", audioBytes)
                    legend(dataColor, "전사·요약", dataBytes)
                }
            }
            .padding(.vertical, 4)

            Button {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Text("오디오만 삭제")
                        .foregroundStyle(.red)
                    Spacer()
                    Text("회의록은 유지")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
        .task { refresh() }
        .confirmationDialog("오디오만 삭제할까요?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("오디오 삭제", role: .destructive) { deleteAudioOnly() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("회의록은 유지됩니다. 발화 재생은 더 이상 할 수 없어요.")
        }

        perMeetingSection
    }

    /// 항상 가득 찬 2색 막대 = 구성비 (소진 게이지 아님)
    private var compositionBar: some View {
        GeometryReader { geo in
            let total = max(audioBytes + dataBytes, 1)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DesignTokens.accent)
                    .frame(width: geo.size.width * CGFloat(audioBytes) / CGFloat(total))
                Rectangle().fill(dataColor)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)   // 아래 범례가 같은 내용을 읽어 준다
    }

    private func legend(_ color: Color, _ label: String, _ bytes: Int64) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label) \(StorageCalc.byteText(bytes))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    /// 회의별 오디오 용량 + 개별 삭제 (PRD F11-2)
    @ViewBuilder
    private var perMeetingSection: some View {
        if !audioMeetings.isEmpty {
            Section {
                ForEach(audioMeetings) { meeting in
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
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("오디오 삭제", role: .destructive) {
                            removeAudio(meeting)
                            try? modelContext.save()
                            refresh()
                        }
                    }
                }
            } header: {
                Text("회의별 오디오")
            } footer: {
                Text("왼쪽으로 밀어 오디오만 지울 수 있어요. 회의록은 남습니다.")
            }
        }
    }

    private func refresh() {
        audioBytes = StorageCalc.directorySize(AudioFileStore.root)
        dataBytes = StorageCalc.dataStoreBytes()
    }

    /// 완료된 회의의 m4a만 삭제 — 처리 중·녹음됨 상태의 오디오는 제외 (08-m5 §4)
    private func deleteAudioOnly() {
        let raw = MeetingStatus.done.rawValue
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.statusRaw == raw })
        for meeting in (try? modelContext.fetch(descriptor)) ?? [] {
            removeAudio(meeting)
        }
        try? modelContext.save()
        refresh()
    }

    private func removeAudio(_ meeting: Meeting) {
        try? FileManager.default.removeItem(
            at: AudioFileStore.m4aURL(meetingID: meeting.id))
        meeting.audioFileName = nil
        meeting.audioSize = 0
    }
}
