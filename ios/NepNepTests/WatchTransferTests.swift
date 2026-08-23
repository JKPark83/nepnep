import XCTest
@testable import NepNep

/// 워치 ↔ 아이폰 전송 경계 (이슈 #15).
/// 여기서 어긋나면 두 앱이 서로 다른 버전으로 깔린 사용자에게서만 터지므로 재현이 어렵다.
final class WatchTransferTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let envelope = WatchRecordingEnvelope(
            meetingID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            typeRaw: "general",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 372.5,
            gapRanges: [GapRange(start: 10, end: 12.5)])

        let dictionary = WatchPayload.encode(envelope, key: WatchPayload.envelopeKey)
        let decoded = WatchPayload.decode(WatchRecordingEnvelope.self,
                                          key: WatchPayload.envelopeKey,
                                          from: dictionary)

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded?.version, WatchRecordingEnvelope.currentVersion)
        XCTAssertEqual(decoded?.audioFormat, "m4a")
    }

    /// 다른 키로 들어온 사전이나 빈 사전은 조용히 nil이어야 한다 — 반쯤 해석하면 안 된다.
    func testDecodeRejectsForeignPayload() {
        let envelope = WatchRecordingEnvelope(meetingID: UUID(), typeRaw: "general",
                                              startedAt: .now, duration: 1)
        let dictionary = WatchPayload.encode(envelope, key: WatchPayload.contextKey)

        XCTAssertNil(WatchPayload.decode(WatchRecordingEnvelope.self,
                                         key: WatchPayload.envelopeKey, from: dictionary))
        XCTAssertNil(WatchPayload.decode(WatchRecordingEnvelope.self,
                                         key: WatchPayload.envelopeKey, from: [:]))
    }

    func testContextRoundTrip() {
        let payload = WatchContextPayload(
            rows: [WatchMeetingRow(id: UUID(), title: "예산 회의",
                                   metaText: "오늘 오후 2:00 · 48분 · 일반",
                                   statusText: "완료", oneLiner: "예산안을 다음 주까지 확정한다.")],
            defaultTypeRaw: "general")

        let dictionary = WatchPayload.encode(payload, key: WatchPayload.contextKey)
        XCTAssertEqual(WatchPayload.decode(WatchContextPayload.self,
                                           key: WatchPayload.contextKey, from: dictionary),
                       payload)
    }

    func testTruncatedMarksCutoff() {
        XCTAssertEqual(WatchPayload.truncated("짧은 제목", limit: 10), "짧은 제목")
        XCTAssertEqual(WatchPayload.truncated("가나다라마바사", limit: 3), "가나다…")
        // 경계에서는 자르지 않는다
        XCTAssertEqual(WatchPayload.truncated("가나다", limit: 3), "가나다")
    }

    /// 워치가 모르는 유형을 보내와도 아이폰이 자기 기본값으로 받아 낸다.
    /// (한 번도 동기화되지 않은 워치는 빈 문자열을 보낸다 — `WatchRecorder.stop` 참고)
    func testUnknownTypeRawFallsBack() {
        XCTAssertNil(MeetingType(rawValue: ""))
        XCTAssertNil(MeetingType(rawValue: "무언가-새-유형"))
    }

    func testWatchDisplayTextCoversEveryStatus() {
        for status in [MeetingStatus.recording, .recorded, .pendingTransfer,
                       .processing, .done, .failed] {
            XCTAssertFalse(status.watchDisplayText.isEmpty, "\(status)")
        }
    }
}
