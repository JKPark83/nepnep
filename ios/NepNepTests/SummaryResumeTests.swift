import XCTest
@testable import NepNep

/// 긴 회의가 요청 제한에 걸려 중간에 죽던 문제 (#21)
final class SummaryResumeTests: XCTestCase {
    /// 모델이 실제로 던지는 문구. 공백이 들어간 "rate limited"라 붙여 쓴 검사만으로는 못 잡았다.
    private struct FakeError: Error, CustomStringConvertible {
        let description: String
    }

    private let rateLimited = FakeError(
        description: "Request has been rate limited. Please try again later.")

    func testRateLimitErrorIsRecognized() {
        XCTAssertTrue(SummaryService.isRateLimitError(rateLimited))
        XCTAssertFalse(SummaryService.isRateLimitError(FakeError(description: "guardrailViolation")))
    }

    /// 실패 문구는 "다시 시도하면 이어서 한다"까지 알려 줘야 한다 — 실제로 이어받기 때문
    func testRateLimitFailureMessageMentionsResume() {
        let message = SummaryService.failureMessage(for: rateLimited)
        XCTAssertTrue(message.contains("이어서"), message)
        XCTAssertNotEqual(message, "요약 중 문제가 생겼어요.")
    }

    func testCheckpointCompletion() {
        XCTAssertFalse(DigestCheckpoint(chunkCount: 18, completedChunks: 9, digests: []).isComplete)
        XCTAssertTrue(DigestCheckpoint(chunkCount: 18, completedChunks: 18, digests: []).isComplete)
        // 구간이 0이면 "다 했다"로 볼 수 없다 — 빈 캐시로 map을 건너뛰면 요약이 비어 버린다
        XCTAssertFalse(DigestCheckpoint(chunkCount: 0, completedChunks: 0, digests: []).isComplete)
    }

    /// 중간 저장본이 파일로 남아 다음 실행이 읽을 수 있어야 한다
    func testCheckpointRoundTrip() throws {
        let id = UUID()
        defer { try? FileManager.default.removeItem(at: AudioFileStore.directory(for: id)) }

        let digest = ChunkDigest(topic: "로드맵",
                                 points: ["화자 1 — 일정 촉박"],
                                 decisions: [],
                                 actionItems: [],
                                 openIssues: [],
                                 place: "",
                                 absentees: "")
        try DigestStore.save(DigestCheckpoint(chunkCount: 18, completedChunks: 9, digests: [digest]),
                             meetingID: id)

        let loaded = try XCTUnwrap(DigestStore.load(meetingID: id))
        XCTAssertEqual(loaded.chunkCount, 18)
        XCTAssertEqual(loaded.completedChunks, 9)
        XCTAssertEqual(loaded.digests.count, 1)
        XCTAssertEqual(loaded.digests[0].points, ["화자 1 — 일정 촉박"])
        XCTAssertFalse(loaded.isComplete)
    }

    /// 재시도 간격은 비어 있으면 안 된다 — 비면 즉시 재시도라 제한이 풀릴 틈이 없다
    func testBackoffIsIncreasing() {
        let backoff = SummaryService.rateLimitBackoff
        XCTAssertFalse(backoff.isEmpty)
        XCTAssertEqual(backoff, backoff.sorted())
    }

    /// 실제로 관측된 정체가 165초라, 총 대기가 그보다 넉넉히 길어야 버틸 수 있다
    func testBackoffOutlastsObservedStall() {
        XCTAssertGreaterThan(SummaryService.rateLimitBackoff.reduce(0, +), 300)
    }

    /// 진행 중인 실행은 이벤트마다 같은 기록을 갈아 끼워야 한다 —
    /// 이벤트 수만큼 기록이 늘어나면 5건 한도가 한 번의 실행으로 다 차 버린다
    func testUpsertReplacesSameRunInsteadOfPilingUp() {
        SummaryDiagnostics.clear()
        defer { SummaryDiagnostics.clear() }

        let id = UUID()
        func record(_ events: [String], inProgress: Bool) -> SummaryRunRecord {
            SummaryRunRecord(id: id, meetingTitle: "긴 회의", startedAt: Date(),
                             duration: 1, outcome: "진행 중", succeeded: false,
                             events: events, inProgress: inProgress)
        }
        SummaryDiagnostics.upsert(record(["요약 시작"], inProgress: true))
        SummaryDiagnostics.upsert(record(["요약 시작", "map 1/18 완료"], inProgress: true))
        SummaryDiagnostics.upsert(record(["요약 시작", "map 1/18 완료", "완료"], inProgress: false))

        XCTAssertEqual(SummaryDiagnostics.records.count, 1)
        XCTAssertEqual(SummaryDiagnostics.records[0].events.count, 3)
        XCTAssertFalse(SummaryDiagnostics.records[0].inProgress)
    }

    /// 추정 진행률은 실제 진행을 앞질러 100%를 만들면 안 된다 — 끝나기 전에 다 찬 막대는 거짓말이다
    func testCreepTargetNeverCompletesEarly() {
        for step in stride(from: 0.0, through: 0.99, by: 0.05) {
            XCTAssertLessThanOrEqual(SummarizingIndicator.creepTarget(for: step), 0.99)
            XCTAssertGreaterThanOrEqual(SummarizingIndicator.creepTarget(for: step), step)
        }
        // reduce 구간(0.9)에서도 막대가 나아갈 여지가 있어야 멈춰 보이지 않는다
        XCTAssertGreaterThan(SummarizingIndicator.creepTarget(for: 0.9), 0.9)
        XCTAssertEqual(SummarizingIndicator.creepTarget(for: 1), 1)
    }

    /// 제한에 걸릴 때마다 호출 간격이 벌어지고, 마지막 단계에서 멈춘다
    func testPacerWidensGapThenSaturates() {
        let pacer = RequestPacer()
        XCTAssertEqual(pacer.gapSeconds, 0, "걸리기 전에는 쉬지 않는다")

        var seen = [pacer.gapSeconds]
        for _ in 0..<10 {
            pacer.slowDown()
            seen.append(pacer.gapSeconds)
        }
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertEqual(pacer.gapSeconds, RequestPacer.gapLadder.last)
    }
}
