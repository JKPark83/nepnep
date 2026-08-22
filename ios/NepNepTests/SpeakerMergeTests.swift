import Foundation
import SwiftData
import Testing
@testable import NepNep

/// 화자 병합·되돌리기·대표 발화 (04-m2 완료 기준: 3케이스 이상)
/// serialized: 동일 스키마 ModelContainer 병렬 생성 시 SwiftData 크래시 회피
@Suite(.serialized)
@MainActor
struct SpeakerMergeTests {
    private func makeMeeting(context: ModelContext) -> (Meeting, [Speaker]) {
        let meeting = Meeting(title: "테스트 회의", type: .general)
        context.insert(meeting)
        let s1 = Speaker(label: "화자 1", colorIndex: 0)
        let s2 = Speaker(label: "화자 2", colorIndex: 1)
        let s3 = Speaker(label: "화자 3", colorIndex: 2)
        meeting.speakers.append(contentsOf: [s1, s2, s3])
        meeting.utterances.append(contentsOf: [
            Utterance(speakerID: s1.id, text: "안녕하세요",
                      startTime: 0, endTime: 2, confidence: 0.9, orderIndex: 0),
            Utterance(speakerID: s2.id, text: "네 반갑습니다",
                      startTime: 2, endTime: 7, confidence: 0.9, orderIndex: 1),
            Utterance(speakerID: s2.id, text: "회의 시작하죠",
                      startTime: 7, endTime: 10, confidence: 0.9, orderIndex: 2),
            Utterance(speakerID: s3.id, text: "자료 공유드립니다",
                      startTime: 10, endTime: 20, confidence: 0.9, orderIndex: 3),
            Utterance(speakerID: s3.id, text: "짧은 답",
                      startTime: 20, endTime: 21, confidence: 0.9, orderIndex: 4),
        ])
        try? context.save()
        return (meeting, [s1, s2, s3])
    }

    /// 컨테이너를 반환값으로 유지 — mainContext만 반환하면 컨테이너가 해제돼 크래시
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Meeting.self, Speaker.self, Utterance.self, Summary.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func 병합하면_발화가_재배정되고_화자수가_준다() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (meeting, speakers) = makeMeeting(context: context)

        _ = SpeakerMerger.merge([speakers[2]], into: speakers[1], meeting: meeting)

        #expect(meeting.speakers.count == 2)
        #expect(!meeting.speakers.contains(where: { $0.id == speakers[2].id }))
        #expect(SpeakerMerger.utteranceCount(of: speakers[1], in: meeting) == 4)
        #expect(meeting.utterances.allSatisfy { $0.speakerID != speakers[2].id })
    }

    @Test func 되돌리면_재배정과_화자가_복원된다() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (meeting, speakers) = makeMeeting(context: context)

        let token = SpeakerMerger.merge([speakers[2]], into: speakers[1], meeting: meeting)
        SpeakerMerger.undo(token, meeting: meeting)

        #expect(meeting.speakers.count == 3)
        #expect(SpeakerMerger.utteranceCount(of: speakers[1], in: meeting) == 2)
        #expect(SpeakerMerger.utteranceCount(of: speakers[2], in: meeting) == 2)
    }

    @Test func 확정하면_병합된_화자가_삭제된다() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (meeting, speakers) = makeMeeting(context: context)
        let removedID = speakers[2].id

        let token = SpeakerMerger.merge([speakers[2]], into: speakers[1], meeting: meeting)
        SpeakerMerger.finalize(token, context: context)

        let remaining = try context.fetch(FetchDescriptor<Speaker>())
        #expect(!remaining.contains(where: { $0.id == removedID }))
        #expect(meeting.speakers.count == 2)
    }

    @Test func 대표발화는_길이순_상위3개다() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (meeting, speakers) = makeMeeting(context: context)
        // 화자 3에 발화 추가 → 4개 중 긴 순 3개만
        meeting.utterances.append(
            Utterance(speakerID: speakers[2].id, text: "중간 길이 발화",
                      startTime: 21, endTime: 26, confidence: 0.9, orderIndex: 5))

        let reps = SpeakerMerger.representativeUtterances(of: speakers[2], in: meeting)

        #expect(reps.count == 3)
        #expect(reps[0].text == "자료 공유드립니다")   // 10초
        #expect(reps[1].text == "중간 길이 발화")       // 5초
        #expect(reps[2].text == "짧은 답")              // 1초
    }

    @Test func 여러화자_동시병합() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (meeting, speakers) = makeMeeting(context: context)

        _ = SpeakerMerger.merge([speakers[1], speakers[2]],
                                into: speakers[0], meeting: meeting)

        #expect(meeting.speakers.count == 1)
        #expect(SpeakerMerger.utteranceCount(of: speakers[0], in: meeting) == 5)
    }
}
