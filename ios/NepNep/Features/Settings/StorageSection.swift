import SwiftData
import SwiftUI

/// 설정 > 저장 공간 (08-m5 §4, 와이어프레임 1h)
///
/// 전체 사용량 막대는 걷어냈다 — 보관량 상한이 없어서(PRD F11-1) 숫자를 봐도
/// 사용자가 할 판단이 없었다. 남긴 건 실제로 쓰는 것, 즉 지우는 길뿐이다.
struct StorageSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Meeting> { $0.audioSize > 0 },
           sort: \Meeting.audioSize, order: .reverse)
    private var audioMeetings: [Meeting]
    @State private var showDeleteConfirm = false

    var body: some View {
        Section("저장 공간") {
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

    /// 완료된 회의의 m4a만 삭제 — 처리 중·녹음됨 상태의 오디오는 제외 (08-m5 §4)
    private func deleteAudioOnly() {
        let raw = MeetingStatus.done.rawValue
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.statusRaw == raw })
        for meeting in (try? modelContext.fetch(descriptor)) ?? [] {
            removeAudio(meeting)
        }
        try? modelContext.save()
    }

    private func removeAudio(_ meeting: Meeting) {
        try? FileManager.default.removeItem(
            at: AudioFileStore.m4aURL(meetingID: meeting.id))
        meeting.audioFileName = nil
        meeting.audioSize = 0
    }
}
