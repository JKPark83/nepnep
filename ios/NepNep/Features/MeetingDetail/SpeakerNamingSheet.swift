import SwiftData
import SwiftUI

/// 화자 이름 지정 + 합치기 시트 (와이어프레임 1f 확정본, 0.75 디텐트)
struct SpeakerNamingSheet: View {
    @Bindable var meeting: Meeting
    let player: AudioPlayerController

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    @State private var pendingUndo: SpeakerMerger.UndoToken?
    @State private var undoExpiry: Task<Void, Never>?

    private var sortedSpeakers: [Speaker] {
        meeting.speakers.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(sortedSpeakers) { speaker in
                            speakerCard(speaker)
                        }
                    }
                    .padding(.horizontal, DesignTokens.margin)
                    .padding(.vertical, 16)
                    .padding(.bottom, 80)
                }
                bottomArea
            }
            .background(DesignTokens.background)
            .navigationTitle("화자")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        try? context.save()
                        dismiss()
                    }
                    .tint(DesignTokens.accent)
                }
            }
        }
        .onDisappear {
            // 시트가 닫히면 대기 중 병합 확정
            finalizePendingUndo()
            try? context.save()
        }
    }

    // MARK: - 화자 카드 (1f: 아바타 + 이름 필드 + N회 + 대표 발화 3개)

    private func speakerCard(_ speaker: Speaker) -> some View {
        let selected = selection.contains(speaker.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    toggleSelection(speaker)
                } label: {
                    ZStack {
                        SpeakerAvatarView(speaker: speaker, size: 36)
                        if selected {
                            Circle()
                                .fill(DesignTokens.accent.opacity(0.85))
                                .frame(width: 36, height: 36)
                            Image(systemName: "checkmark")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                TextField(speaker.label, text: nameBinding(speaker))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(SpeakerMerger.utteranceCount(of: speaker, in: meeting))회")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(SpeakerMerger.representativeUtterances(of: speaker, in: meeting),
                    id: \.orderIndex) { utterance in
                HStack(spacing: 8) {
                    Button {
                        player.play(from: utterance.startTime)
                    } label: {
                        Image(systemName: "play.circle")
                            .foregroundStyle(DesignTokens.accent)
                    }
                    .accessibilityLabel("이 발화 재생")
                    Text(utterance.text)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(MeetingDateFormat.timestamp(utterance.startTime))
                        .font(.caption2.monospaced())
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
        .padding(14)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
                    .stroke(DesignTokens.accent, lineWidth: 1.5)
            }
        }
    }

    private func nameBinding(_ speaker: Speaker) -> Binding<String> {
        Binding(
            get: { speaker.customName ?? "" },
            set: { speaker.customName = $0.isEmpty ? nil : $0 })
    }

    private func toggleSelection(_ speaker: Speaker) {
        if selection.contains(speaker.id) {
            selection.remove(speaker.id)
        } else {
            selection.insert(speaker.id)
        }
    }

    // MARK: - 하단 액션 (합치기 버튼 / 되돌리기 스낵바)

    @ViewBuilder
    private var bottomArea: some View {
        if let token = pendingUndo {
            undoSnackbar(token)
        } else if selection.count >= 2 {
            Button(action: mergeSelected) {
                Text("같은 사람으로 합치기")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, DesignTokens.margin)
            .padding(.bottom, 12)
        }
    }

    private func mergeSelected() {
        finalizePendingUndo()
        let selected = sortedSpeakers.filter { selection.contains($0.id) }
        guard let target = selected.first, selected.count >= 2 else { return }
        let sources = Array(selected.dropFirst())
        pendingUndo = SpeakerMerger.merge(sources, into: target, meeting: meeting)
        selection.removeAll()
        // 5초 뒤 자동 확정 (04-m2 §4)
        undoExpiry = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            finalizePendingUndo()
        }
    }

    private func undoSnackbar(_ token: SpeakerMerger.UndoToken) -> some View {
        HStack {
            Text("화자를 합쳤어요")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("실행 취소") {
                undoExpiry?.cancel()
                SpeakerMerger.undo(token, meeting: meeting)
                pendingUndo = nil
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DesignTokens.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, DesignTokens.margin)
        .padding(.bottom, 12)
    }

    private func finalizePendingUndo() {
        undoExpiry?.cancel()
        guard let token = pendingUndo else { return }
        SpeakerMerger.finalize(token, context: context)
        pendingUndo = nil
    }
}
