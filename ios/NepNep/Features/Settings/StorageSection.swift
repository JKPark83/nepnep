import SwiftData
import SwiftUI

/// 설정 > 저장 공간 (08-m5 §4, 와이어프레임 1h)
struct StorageSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var audioBytes: Int64 = 0
    @State private var dataBytes: Int64 = 0
    @State private var showDeleteConfirm = false

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
                ProgressView(value: Double(audioBytes),
                             total: Double(max(audioBytes + dataBytes, 1)))
                    .tint(DesignTokens.accent)
                Text("오디오 \(StorageCalc.byteText(audioBytes)) · 전사·요약 \(StorageCalc.byteText(dataBytes))")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
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
            try? FileManager.default.removeItem(
                at: AudioFileStore.m4aURL(meetingID: meeting.id))
            meeting.audioFileName = nil
            meeting.audioSize = 0
        }
        try? modelContext.save()
        refresh()
    }
}
