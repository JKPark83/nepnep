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

    // MARK: - 문서 폴더 → 지원 폴더 이사

    /// 파일을 옮기는 코드라 틀리면 남의 녹음이 사라진다. 손으로 확인하기도
    /// 어렵다 — 이미 옮긴 기기에서는 두 번 다시 재현되지 않는다.
    func testMigrationMovesRecordingsOutOfDocuments() throws {
        let (documents, container) = try sandbox()
        let id = UUID().uuidString
        try write("옛 녹음", to: documents, "audio/\(id)/recording.m4a")
        try write("워치 파일", to: documents, "watch-inbox/\(id).m4a")

        AudioFileStore.migrate(from: documents, to: container)

        XCTAssertEqual(read(container, "audio/\(id)/recording.m4a"), "옛 녹음")
        XCTAssertEqual(read(container, "watch-inbox/\(id).m4a"), "워치 파일")
        // 다 옮겼으면 빈 껍데기는 남기지 않는다 — 파일 앱에 빈 폴더가 보인다
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: documents.appendingPathComponent("audio").path))
    }

    /// 목적지에 같은 회의가 이미 있으면 건드리지 않는다.
    /// 새로 녹음한 쪽을 옛것으로 덮어쓰는 편이 훨씬 나쁘다.
    func testMigrationNeverOverwritesNewerRecording() throws {
        let (documents, container) = try sandbox()
        let id = UUID().uuidString
        try write("옛 녹음", to: documents, "audio/\(id)/recording.m4a")
        try write("새 녹음", to: container, "audio/\(id)/recording.m4a")

        AudioFileStore.migrate(from: documents, to: container)

        XCTAssertEqual(read(container, "audio/\(id)/recording.m4a"), "새 녹음")
        // 옮기지 못한 것은 문서 폴더에 그대로 남는다 — 지우면 복구할 길이 없다
        XCTAssertEqual(read(documents, "audio/\(id)/recording.m4a"), "옛 녹음")
    }

    /// 앱을 켤 때마다 도는 코드다. 옮길 게 없으면 조용히 지나가야 한다.
    func testMigrationIsIdempotent() throws {
        let (documents, container) = try sandbox()
        let id = UUID().uuidString
        try write("녹음", to: documents, "audio/\(id)/recording.m4a")

        AudioFileStore.migrate(from: documents, to: container)
        AudioFileStore.migrate(from: documents, to: container)

        XCTAssertEqual(read(container, "audio/\(id)/recording.m4a"), "녹음")
    }

    // MARK: - 조각

    private func sandbox() throws -> (documents: URL, container: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let container = root.appendingPathComponent("Application Support", isDirectory: true)
        for url in [documents, container] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return (documents, container)
    }

    private func write(_ text: String, to base: URL, _ path: String) throws {
        let url = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ base: URL, _ path: String) -> String? {
        try? String(contentsOf: base.appendingPathComponent(path), encoding: .utf8)
    }

    func testAutoTitle() {
        let date = DateComponents(calendar: .current, year: 2026, month: 8, day: 22).date!
        XCTAssertEqual(Meeting.autoTitle(date: date), "8월 22일 회의")
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
        XCTAssertTrue(Meeting.isAutoTitle(Meeting.autoTitle(date: date), date: date))
        // 유형명이 들어가던 시절의 자동 제목도 자동 제목으로 본다 (#21)
        XCTAssertTrue(Meeting.isAutoTitle("8월 22일 스탠드업 회의", date: date))
        XCTAssertTrue(Meeting.isAutoTitle("8월 22일 일반 회의", date: date))
        // 이전 요약이 만든 제목 → 재요약 시 갱신 대상
        XCTAssertTrue(Meeting.isAutoTitle("2026-08-22 - 3분기 로드맵 우선순위 조율", date: date))
        // 사용자가 직접 붙인 이름은 보존
        XCTAssertFalse(Meeting.isAutoTitle("디자인 리뷰 1on1", date: date))
        // 다른 날짜의 접두사는 이 회의 것이 아니다
        XCTAssertFalse(Meeting.isAutoTitle("2026-08-21 - 온보딩 화면 리뷰", date: date))
    }
}
