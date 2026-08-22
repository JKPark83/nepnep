import SwiftUI
import UIKit

/// 전사 발화 목록 (와이어프레임 1e: 아바타 + 이름 + 모노 타임스탬프 + 말풍선)
struct TranscriptListView: View {
    let meeting: Meeting
    let player: AudioPlayerController
    @Environment(\.modelContext) private var modelContext

    private var utterances: [Utterance] {
        meeting.utterances.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var speakerByID: [UUID: Speaker] {
        Dictionary(uniqueKeysWithValues: meeting.speakers.map { ($0.id, $0) })
    }

    /// 재생 위치가 속한 발화 — 재생 중 말풍선 강조 (1e)
    private var playingUtterance: Utterance? {
        guard player.isActive else { return nil }
        let t = player.currentTime
        return utterances.last { $0.startTime <= t && t < $0.endTime + 0.5 }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(utterances, id: \.orderIndex) { utterance in
                row(utterance)
            }
        }
    }

    private func row(_ utterance: Utterance) -> some View {
        let speaker = speakerByID[utterance.speakerID]
        let isPlaying = playingUtterance?.orderIndex == utterance.orderIndex
        return HStack(alignment: .top, spacing: 10) {
            SpeakerAvatarView(speaker: speaker, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(speaker?.displayName ?? "화자")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(MeetingDateFormat.timestamp(utterance.startTime))
                        .font(.caption.monospaced())
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Text(utterance.text)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(12)
                    .background(isPlaying
                                ? DesignTokens.accent.opacity(0.12)
                                : DesignTokens.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            player.play(from: utterance.startTime)   // 발화 탭 → 해당 시점 재생 (F5-3)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = utterance.text
            } label: {
                Label("복사", systemImage: "doc.on.doc")
            }
            Button {
                addTodo(from: utterance)
            } label: {
                Label("할 일로 추가", systemImage: "checklist")
            }
        }
    }

    /// 길게 눌러 발화를 할 일로 추가 (1e 인터랙션 노트) — 요약이 없으면 빈 요약을 만들어 담는다
    private func addTodo(from utterance: Utterance) {
        let summary: Summary
        if let existing = meeting.summary {
            summary = existing
        } else {
            summary = Summary(templateTypeRaw: meeting.type.rawValue)
            meeting.summary = summary
        }
        let nextIndex = (summary.todos.map(\.orderIndex).max() ?? -1) + 1
        summary.todos.append(TodoItem(text: utterance.text, orderIndex: nextIndex))
        try? modelContext.save()
    }
}

/// 화자 색 아바타 (colorIndex → DesignTokens.speakerColors)
struct SpeakerAvatarView: View {
    let speaker: Speaker?
    var size: CGFloat = 28

    var body: some View {
        let color = DesignTokens.speakerColors[
            (speaker?.colorIndex ?? 0) % DesignTokens.speakerColors.count]
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private var initial: String {
        guard let name = speaker?.displayName, let first = name.first else { return "?" }
        // "화자 3" → "3", 이름 지정 시 첫 글자
        if let number = name.split(separator: " ").last, number.allSatisfy(\.isNumber) {
            return String(number)
        }
        return String(first)
    }
}
