#if DEBUG
import Foundation
import SwiftData

/// 시뮬레이터 UI 확인용 데모 데이터 (`-seedDemo` 런치 인자)
/// 릴리스 빌드에는 포함되지 않는다.
enum DebugSeed {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemo")
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard isEnabled else { return }
        // 항상 초기화 후 다시 심어 상태를 고정
        try? context.delete(model: Meeting.self)

        context.insert(makeDoneMeeting())
        context.insert(makeProcessingMeeting())
        context.insert(makeFailedMeeting())
        try? context.save()
    }

    private static func makeDoneMeeting() -> Meeting {
        let meeting = Meeting(title: "8월 22일 일반 회의", type: .general,
                              createdAt: .now.addingTimeInterval(-3 * 3600))
        meeting.duration = 48 * 60
        meeting.status = .done
        meeting.processingProgress = 1

        let s1 = Speaker(label: "화자 1", colorIndex: 0)
        let s2 = Speaker(label: "화자 2", colorIndex: 1)
        let s3 = Speaker(label: "화자 3", colorIndex: 2)
        meeting.speakers.append(contentsOf: [s1, s2, s3])

        let script: [(Speaker, String, TimeInterval, TimeInterval)] = [
            (s1, "다들 오셨으니 시작할게요. 오늘은 3분기 로드맵 우선순위를 정하는 자리예요.", 0, 8),
            (s2, "네, 지난주에 공유드린 초안 기준으로 말씀드리면 온보딩 개선이 가장 급합니다.", 9, 17),
            (s3, "저도 동의해요. 다만 리소스가 겹치는 결제 개편 일정과 조율이 필요해 보여요.", 18, 26),
            (s1, "결제 개편은 언제까지 마무리 가능할까요?", 27, 31),
            (s2, "QA까지 포함하면 9월 둘째 주가 현실적입니다.", 32, 38),
            (s3, "그럼 온보딩 개선은 9월 셋째 주 착수로 잡고, 그 전까지 설계를 끝내두겠습니다.", 39, 48),
            (s1, "좋아요. 액션 아이템 정리해서 오늘 중으로 공유해 주세요.", 49, 55),
            (s2, "네, 회의 끝나고 바로 정리해서 올리겠습니다.", 56, 61),
        ]
        for (i, line) in script.enumerated() {
            meeting.utterances.append(Utterance(
                speakerID: line.0.id, text: line.1,
                startTime: line.2, endTime: line.3,
                confidence: 0.92, orderIndex: i))
        }

        // M3 요약 카드 UI 확인용 데모 요약
        let summary = Summary(
            templateTypeRaw: MeetingType.general.rawValue,
            oneLiner: "3분기 로드맵에서 결제 개편을 9월 둘째 주까지 마치고 온보딩 개선을 셋째 주에 착수하기로 했다.",
            sections: [
                SummarySection(title: "주요 논의", bullets: [
                    "3분기 로드맵 우선순위 검토 — 온보딩 개선이 가장 시급",
                    "결제 개편과 온보딩 개선의 리소스 중복 문제",
                ]),
                SummarySection(title: "결정사항", bullets: [
                    "결제 개편은 QA 포함 9월 둘째 주까지 마무리",
                    "온보딩 개선은 9월 셋째 주 착수, 그 전까지 설계 완료",
                ]),
            ])
        meeting.summary = summary
        summary.todos.append(TodoItem(text: "액션 아이템 정리해서 공유",
                                      assignee: "화자 2", due: "오늘",
                                      isDone: true, orderIndex: 0))
        summary.todos.append(TodoItem(text: "온보딩 개선 설계 문서 작성",
                                      assignee: "화자 3", due: "9월 둘째 주",
                                      orderIndex: 1))
        summary.todos.append(TodoItem(text: "결제 개편 QA 일정 확정",
                                      orderIndex: 2))
        return meeting
    }

    private static func makeProcessingMeeting() -> Meeting {
        let meeting = Meeting(title: "디자인 리뷰 1on1", type: .oneOnOne,
                              createdAt: .now.addingTimeInterval(-30 * 60))
        meeting.duration = 22 * 60
        meeting.status = .processing
        meeting.processingStage = "받아쓰는 중"
        meeting.processingProgress = 0.42
        return meeting
    }

    private static func makeFailedMeeting() -> Meeting {
        let meeting = Meeting(title: "8월 21일 스탠드업 회의", type: .standup,
                              createdAt: .now.addingTimeInterval(-26 * 3600))
        meeting.duration = 15 * 60
        meeting.status = .failed
        meeting.failureReasonRaw = ProcessingFailureReason.engineError.rawValue
        return meeting
    }
}
#endif
