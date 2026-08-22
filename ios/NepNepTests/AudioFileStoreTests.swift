import XCTest
@testable import NepNep

final class AudioFileStoreTests: XCTestCase {
    func testPathConvention() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertTrue(AudioFileStore.chunkURL(meetingID: id, index: 7).path
            .hasSuffix("audio/\(id.uuidString)/chunk-007.caf"))
        XCTAssertTrue(AudioFileStore.mergedCafURL(meetingID: id).path
            .hasSuffix("audio/\(id.uuidString)/recording.caf"))
        XCTAssertTrue(AudioFileStore.m4aURL(meetingID: id).path
            .hasSuffix("audio/\(id.uuidString)/recording.m4a"))
    }

    func testChunkURLsSortedAndFiltered() throws {
        let id = UUID()
        try AudioFileStore.createDirectory(for: id)
        defer { AudioFileStore.removeDirectory(for: id) }

        let dir = AudioFileStore.directory(for: id)
        for name in ["chunk-002.caf", "chunk-000.caf", "chunk-001.caf", "recording.caf", "note.txt"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path,
                                           contents: Data())
        }
        let urls = AudioFileStore.chunkURLs(meetingID: id)
        XCTAssertEqual(urls.map(\.lastPathComponent),
                       ["chunk-000.caf", "chunk-001.caf", "chunk-002.caf"])
    }

    func testAutoTitle() {
        let date = DateComponents(calendar: .current, year: 2026, month: 8, day: 22).date!
        XCTAssertEqual(Meeting.autoTitle(type: .general, date: date), "8월 22일 일반 회의")
        XCTAssertEqual(Meeting.autoTitle(type: .standup, date: date), "8월 22일 스탠드업 회의")
    }

    func testSummaryTitle() {
        let date = DateComponents(calendar: .current, year: 2026, month: 8, day: 22).date!
        XCTAssertEqual(Meeting.summaryTitle(topic: "3분기 로드맵 우선순위 조율", date: date),
                       "2026-08-22 - 3분기 로드맵 우선순위 조율")
        // 모델이 앞뒤 공백·줄바꿈을 붙여 오는 경우
        XCTAssertEqual(Meeting.summaryTitle(topic: "  킥오프 일정 조율\n", date: date),
                       "2026-08-22 - 킥오프 일정 조율")
        // 주제가 비면 nil — 호출 측이 기존 제목을 유지한다
        XCTAssertNil(Meeting.summaryTitle(topic: "", date: date))
        XCTAssertNil(Meeting.summaryTitle(topic: "   ", date: date))
    }

    func testIsAutoTitle() {
        let date = DateComponents(calendar: .current, year: 2026, month: 8, day: 22).date!
        // 유형별 자동 제목 — 녹음 중 유형을 바꾼 경우까지 포함
        for type in MeetingType.allCases {
            XCTAssertTrue(Meeting.isAutoTitle(Meeting.autoTitle(type: type, date: date), date: date))
        }
        // 이전 요약이 만든 제목 → 재요약 시 갱신 대상
        XCTAssertTrue(Meeting.isAutoTitle("2026-08-22 - 3분기 로드맵 우선순위 조율", date: date))
        // 사용자가 직접 붙인 이름은 보존
        XCTAssertFalse(Meeting.isAutoTitle("디자인 리뷰 1on1", date: date))
        // 다른 날짜의 접두사는 이 회의 것이 아니다
        XCTAssertFalse(Meeting.isAutoTitle("2026-08-21 - 온보딩 화면 리뷰", date: date))
    }
}
