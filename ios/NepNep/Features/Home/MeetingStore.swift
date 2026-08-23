import Foundation
import SwiftData

/// 홈 목록 쿼리·검색·삭제 (04-m2 §1)
@MainActor
@Observable
final class MeetingStore {
    var searchText = ""

    /// 제목 + 전사 본문 검색 (F4-4). @Query 결과를 인메모리 필터.
    /// 회의 수백 건 규모까지는 충분 — 성능 문제 시 오픈 이슈 E(FTS)로 이관.
    func filtered(_ all: [Meeting]) -> [Meeting] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { meeting in
            meeting.title.localizedStandardContains(q)
                || meeting.utterances.contains { $0.text.localizedStandardContains(q) }
        }
    }

    func delete(_ meeting: Meeting, context: ModelContext) {
        AudioFileStore.removeDirectory(for: meeting.id)
        context.delete(meeting)   // Speaker·Utterance·Summary는 cascade
        try? context.save()
        PhoneWatchSession.shared.pushContext()   // 워치 목록에 지운 회의가 남지 않게 (이슈 #15 §5)
    }
}

/// 홈 카드 메타 표기 (와이어프레임 1b: "오늘 오후 2:00 · 48분 · 일반")
enum MeetingDateFormat {
    static func relative(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let time = timeString(date)
        if cal.isDate(date, inSameDayAs: now) { return "오늘 \(time)" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) { return "어제 \(time)" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return "\(fmt.string(from: date)) \(time)"
    }

    static func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "a h:mm"
        return fmt.string(from: date)
    }

    /// "48분", "1시간 12분"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds) / 60
        let h = total / 60
        let m = total % 60
        if h > 0 { return m > 0 ? "\(h)시간 \(m)분" : "\(h)시간" }
        return "\(max(m, 1))분"
    }

    /// 전사 타임스탬프 "mm:ss"
    static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
