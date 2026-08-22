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
}
