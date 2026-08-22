import Foundation
import SwiftData

/// 화자 병합·되돌리기 (04-m2 §4, F5-6)
/// 병합 직후에는 관계만 바꾸고 모델 삭제는 finalize에서 — 스낵바 5초 내 되돌리기 대비.
@MainActor
enum SpeakerMerger {
    struct UndoToken {
        let target: Speaker
        let removed: [Speaker]
        let reassigned: [(utterance: Utterance, oldSpeakerID: UUID)]
    }

    /// sources의 발화를 전부 target으로 재배정하고 sources를 목록에서 제거
    static func merge(_ sources: [Speaker], into target: Speaker,
                      meeting: Meeting) -> UndoToken {
        let sourceIDs = Set(sources.map(\.id))
        var reassigned: [(Utterance, UUID)] = []
        for utterance in meeting.utterances where sourceIDs.contains(utterance.speakerID) {
            reassigned.append((utterance, utterance.speakerID))
            utterance.speakerID = target.id
        }
        meeting.speakers.removeAll { sourceIDs.contains($0.id) }
        return UndoToken(target: target, removed: sources, reassigned: reassigned)
    }

    /// 스낵바 "실행 취소" — 재배정 원복 + 화자 복원
    static func undo(_ token: UndoToken, meeting: Meeting) {
        for (utterance, oldID) in token.reassigned {
            utterance.speakerID = oldID
        }
        meeting.speakers.append(contentsOf: token.removed)
    }

    /// 되돌리기 시한 경과 — 분리된 화자 모델을 실제 삭제
    static func finalize(_ token: UndoToken, context: ModelContext) {
        for speaker in token.removed {
            context.delete(speaker)
        }
        try? context.save()
    }

    static func utteranceCount(of speaker: Speaker, in meeting: Meeting) -> Int {
        meeting.utterances.count { $0.speakerID == speaker.id }
    }

    /// 대표 발화 — 길이(발화 시간)가 긴 순으로 상위 limit개 (와이어프레임 1f)
    static func representativeUtterances(of speaker: Speaker, in meeting: Meeting,
                                         limit: Int = 3) -> [Utterance] {
        meeting.utterances
            .filter { $0.speakerID == speaker.id }
            .sorted { ($0.endTime - $0.startTime) > ($1.endTime - $1.startTime) }
            .prefix(limit)
            .map { $0 }
    }
}
