import Foundation
import FoundationModels
import SwiftData
import UIKit

/// Foundation Models map-reduce 요약 오케스트레이션 (05-m3 §4, #21 개편)
///
/// [Utterance…] → Chunker → 청크별 세션(ChunkDigest)     // map (순차 — 발열 고려)
///              → digests 병합 → 새 세션(FinalSummary)    // reduce
///              → 한도 초과 시 digest를 절반씩 압축하며 재귀적으로 재시도
///
/// 모델 지시만으로는 개수·중복·자리표시자가 통제되지 않아, 저장 직전에
/// SummaryTemplates의 후처리를 한 번 더 태운다.
struct SummaryService {
    /// 이 요약 한 번 동안의 호출 간격을 기억한다 (구조체 밖의 참조형이라 값 복사에도 유지된다)
    let pacer = RequestPacer()

    /// 사용자가 설정에 적어 둔 회의 용어 (#21 후속).
    /// 전사 단계에서는 실을 방법이 없어서 — `TranscriptionGlossary` 주석 참고 —
    /// 요약 프롬프트에 실어 표기만이라도 바로잡는다.
    var glossary: [String] = TranscriptionGlossary.terms

    /// 온디바이스 모델 가용 여부 — 비가용 시 요약을 건너뛴다 (처리 전체는 성공)
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - 전체 파이프라인

    /// digests 저장본이 있으면 map을 생략하고 reduce만 재실행한다 (재요약, 05-m3 §5)
    /// - Parameter onNotice: 쉬는 중처럼 사용자에게 알려야 할 상태 한 줄 (없으면 nil)
    @MainActor
    static func generate(meeting: Meeting,
                         context: ModelContext,
                         onProgress: @escaping (Double) -> Void = { _ in },
                         onNotice: @escaping (String?) -> Void = { _ in }) async throws {
        let log = SummaryRunLog(meetingTitle: meeting.title)
        // 요약 중 화면이 꺼지면 앱이 백그라운드로 내려가고, 그때부터 모델 요청 제한이
        // 훨씬 빨리 걸린다. 긴 회의는 몇 분씩 걸리므로 그동안만 잠금을 막는다 (#21).
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            onNotice(nil)
        }
        do {
            try await run(meeting: meeting, context: context, log: log,
                          onProgress: onProgress, onNotice: onNotice)
            meeting.summaryFailureReason = nil
            log.finish(outcome: "성공", succeeded: true)
        } catch {
            let reason = failureMessage(for: error)
            meeting.summaryFailureReason = reason
            log.event("에러: \(errorDetail(error))")
            log.finish(outcome: reason, succeeded: false)
            throw error
        }
    }

    @MainActor
    private static func run(meeting: Meeting,
                            context: ModelContext,
                            log: SummaryRunLog,
                            onProgress: @escaping (Double) -> Void,
                            onNotice: @escaping (String?) -> Void) async throws {
        let service = SummaryService()
        onNotice("회의 내용을 불러오는 중")
        let speakers = speakerNames(meeting: meeting)
        let saved = DigestStore.load(meetingID: meeting.id)
        let digests: [ChunkDigest]
        if let saved, saved.isComplete {
            log.event("구간 요지 캐시 사용 — \(saved.digests.count)구간, map 생략")
            digests = saved.digests
            onProgress(0.9)
        } else {
            let lines = transcriptLines(meeting: meeting)
            guard !lines.isEmpty else {
                log.event("전사가 비어 있어 요약을 건너뜀")
                return
            }
            let charCount = lines.reduce(0) { $0 + $1.count }
            log.event("전사 \(lines.count)줄 · \(charCount)자 · 화자 \(speakers.count)명")
            let meetingID = meeting.id
            digests = try await service.makeDigests(
                lines: lines,
                speakers: speakers,
                resuming: saved,
                log: log,
                onProgress: { onProgress($0 * 0.9) },   // map 0~0.9, reduce 0.9~1
                onNotice: onNotice,
                // 구간 하나가 끝날 때마다 저장한다 — 중간에 실패해도 여기까지는 남는다 (#21)
                onCheckpoint: { try? DigestStore.save($0, meetingID: meetingID) })
        }
        let final = try await service.finalize(digests: digests, speakers: speakers,
                                               log: log, onNotice: onNotice)
        apply(final, digests: digests, to: meeting, context: context, log: log)
        onProgress(1)
    }

    @MainActor
    static func transcriptLines(meeting: Meeting) -> [String] {
        let names = Dictionary(uniqueKeysWithValues: meeting.speakers.map { ($0.id, $0.displayName) })
        return meeting.utterances
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { "\(names[$0.speakerID] ?? "화자"): \($0.text)" }
    }

    /// 프롬프트에 넣을 화자 명단 — 모델이 명단 밖 화자를 지어내면 후처리에서 걸러낸다
    @MainActor
    static func speakerNames(meeting: Meeting) -> [String] {
        meeting.speakers.map(\.displayName)
    }

    /// FinalSummary + 구간 요지 → Summary/TodoItem 반영 (기존 요약 교체).
    ///
    /// 서술부(제목·한 줄·세 줄·안건)는 모델이 쓴 final을 쓰고,
    /// 표(결정·할 일·보류)와 머리말(장소·불참)은 구간 요지에서 코드가 병합한다.
    /// reduce에 표까지 다시 물으면 모델 호출과 출력 길이만 늘고, 중복 제거는 코드가 더 정확하다 (#21).
    @MainActor
    static func apply(_ final: FinalSummary,
                      digests: [ChunkDigest],
                      to meeting: Meeting,
                      context: ModelContext,
                      log: SummaryRunLog? = nil) {
        if let old = meeting.summary {
            meeting.summary = nil
            context.delete(old)
        }
        // 브리핑만 모델이 자유롭게 쓰는 값이라 지어낸 문장이 섞인다.
        // 구간 요지에 뿌리내리지 못한 줄은 여기서 떨어뜨린다 (#21).
        let source = SummaryTemplates.digestText(digests)
        let briefing = SummaryTemplates.cleanBullets(
            SummaryTemplates.grounded(final.briefing, in: source),
            limit: SummaryTemplates.briefingLines,
            minLength: SummaryTemplates.minSentenceLength)
        let decisions = SummaryTemplates.mergeDecisions(digests.flatMap(\.decisions))
        let todos = SummaryTemplates.cleanActionItems(digests.flatMap(\.actionItems))
        let openIssues = SummaryTemplates.mergeOpenIssues(digests.flatMap(\.openIssues))
        let agenda = SummaryTemplates.cleanAgenda(final.agenda)
        log?.event("정리 결과 — 브리핑 \(briefing.count) · 안건 \(agenda.count) · "
                   + "결정 \(decisions.count) · 할 일 \(todos.count) · 보류 \(openIssues.count)")

        let summary = Summary(
            templateTypeRaw: MeetingType.general.rawValue,
            oneLiner: final.oneLiner.trimmingCharacters(in: .whitespacesAndNewlines),
            sections: SummaryTemplates.exportSections(briefing: briefing,
                                                      decisions: decisions,
                                                      agenda: agenda,
                                                      openIssues: openIssues))
        summary.briefing = briefing
        summary.decisions = decisions
        summary.agenda = agenda
        summary.parkingLot = openIssues
        summary.place = SummaryTemplates.firstFilled(digests.map(\.place))
        summary.absentees = SummaryTemplates.firstFilled(digests.map(\.absentees))
        meeting.summary = summary
        for (i, item) in todos.enumerated() {
            summary.todos.append(TodoItem(text: item.task,
                                          assignee: item.assignee.isEmpty ? nil : item.assignee,
                                          due: item.due.isEmpty ? nil : item.due,
                                          orderIndex: i,
                                          status: item.status))
        }
        // 자동 제목이면 요약이 뽑은 주제로 교체 — 사용자가 바꾼 제목은 건드리지 않는다
        if Meeting.isAutoTitle(meeting.title, date: meeting.createdAt),
           let generated = Meeting.summaryTitle(topic: final.title, date: meeting.createdAt) {
            meeting.title = generated
        }
        meeting.type = .general
        meeting.summaryUnavailable = false
        try? context.save()
    }

    // MARK: - map

    func makeDigests(lines: [String],
                     speakers: [String],
                     resuming: DigestCheckpoint? = nil,
                     log: SummaryRunLog? = nil,
                     onProgress: (Double) -> Void = { _ in },
                     onNotice: (String?) -> Void = { _ in },
                     onCheckpoint: (DigestCheckpoint) -> Void = { _ in }) async throws -> [ChunkDigest] {
        let chunks = TranscriptChunker.chunk(lines)
        log?.event("구간 \(chunks.count)개로 분할 (최대 \(chunks.map(\.count).max() ?? 0)자)")

        var digests: [ChunkDigest] = []
        var start = 0
        // 구간 수가 같을 때만 이어받는다 — 전사가 바뀌었으면 구간 경계가 어긋나 이어 붙일 수 없다
        if let resuming, resuming.chunkCount == chunks.count, resuming.completedChunks < chunks.count {
            digests = resuming.digests
            start = resuming.completedChunks
            log?.event("지난 실행이 끝낸 \(start)/\(chunks.count)구간을 이어받음")
        }
        onProgress(Double(start) / Double(max(chunks.count, 1)))

        for i in start..<chunks.count {
            // 지금 몇 번째를 붙들고 있는지 화면에 계속 보여 준다 — 진행률만으로는
            // 막힌 것과 오래 걸리는 것을 구분할 수 없었다 (#21)
            onNotice("\(chunks.count)구간 중 \(i + 1)번째 읽는 중")
            let produced = try await withRateLimitRetry("map \(i + 1)", log: log,
                                                        onNotice: onNotice) {
                try await digest(chunkText: chunks[i], speakers: speakers, depth: 0, log: log)
            }
            digests.append(contentsOf: produced)
            onCheckpoint(DigestCheckpoint(chunkCount: chunks.count,
                                          completedChunks: i + 1,
                                          digests: digests))
            log?.event("map \(i + 1)/\(chunks.count) 완료"
                       + (produced.count > 1 ? " (재분할 \(produced.count)개)" : ""))
            onProgress(Double(i + 1) / Double(max(chunks.count, 1)))
        }
        return digests
    }

    /// 모델이 요청 빈도를 제한하면 잠시 쉬었다 다시 시도한다 (#21).
    /// 긴 회의는 모델을 20번 가까이 연달아 부르는데, 한 번 제한에 걸렸다고 그대로 던지면
    /// 그때까지 만든 구간 요지까지 함께 버려졌다.
    private func withRateLimitRetry<T>(_ label: String,
                                       log: SummaryRunLog?,
                                       onNotice: (String?) -> Void = { _ in },
                                       _ body: () async throws -> T) async throws -> T {
        for (attempt, wait) in Self.rateLimitBackoff.enumerated() {
            do {
                try await pacer.pace()
                return try await body()
            } catch {
                guard Self.isRateLimitError(error) else { throw error }
                // 한 번 걸렸으면 남은 호출도 걸린다 — 이후 호출 간격을 벌려 스스로 속도를 낮춘다
                pacer.slowDown()
                log?.event("\(label) 요청 제한 — \(wait)초 쉬고 재시도 "
                           + "(\(attempt + 1)/\(Self.rateLimitBackoff.count)), "
                           + "이후 호출 간격 \(pacer.gapSeconds)초")
                onNotice("요청이 몰려 \(wait)초 쉬는 중이에요")
                try await Task.sleep(for: .seconds(wait))
            }
        }
        try await pacer.pace()
        return try await body()
    }

    /// 재시도 간격(초). 제한이 풀리는 데 실제로 2~3분이 걸리는 것을 확인해
    /// 15·45초만 쉬고 포기하던 것을 총 7분 남짓 버티도록 늘렸다 (#21).
    /// 여기서 포기해도 끝낸 구간은 저장돼 있어 다음 시도가 이어받는다.
    static let rateLimitBackoff = [10, 30, 60, 120, 240]

    /// 컨텍스트 한도 초과 시 청크를 반으로 재분할해 재시도 (05-m3 §4)
    private func digest(chunkText: String,
                        speakers: [String],
                        depth: Int,
                        log: SummaryRunLog?) async throws -> [ChunkDigest] {
        do {
            let session = LanguageModelSession(instructions: SummaryTemplates.mapInstructions)
            let response = try await session.respond(
                to: SummaryTemplates.mapPrompt(chunkText: chunkText, speakers: speakers,
                                               glossary: glossary),
                generating: ChunkDigest.self)
            return [response.content]
        } catch {
            guard Self.isContextWindowError(error), depth < 3, chunkText.count > 200 else {
                throw error
            }
            log?.event("map 구간 컨텍스트 초과 — \(chunkText.count)자를 재분할 (depth \(depth + 1))")
            let lines = chunkText.split(separator: "\n").map(String.init)
            let halves = TranscriptChunker.chunk(lines, limit: max(200, chunkText.count / 2))
            var result: [ChunkDigest] = []
            for half in halves {
                result.append(contentsOf: try await digest(chunkText: half,
                                                           speakers: speakers,
                                                           depth: depth + 1,
                                                           log: log))
            }
            return result
        }
    }

    // MARK: - reduce

    /// 컨텍스트 한도를 넘으면 digest를 절반씩 압축하며 다시 시도한다.
    /// 예전에는 절반 압축을 딱 한 번만 해서, 구간이 아주 많은 긴 회의는 그대로 실패했다 (#21).
    func finalize(digests: [ChunkDigest],
                  speakers: [String],
                  log: SummaryRunLog? = nil,
                  onNotice: (String?) -> Void = { _ in },
                  depth: Int = 0) async throws -> FinalSummary {
        do {
            log?.event("reduce 시도 — 구간 \(digests.count)개 (depth \(depth))")
            onNotice("\(digests.count)구간을 하나로 합치는 중")
            return try await withRateLimitRetry("reduce", log: log, onNotice: onNotice) {
                let session = LanguageModelSession(instructions: SummaryTemplates.reduceInstructions)
                return try await session.respond(
                    to: SummaryTemplates.reducePrompt(digests: digests, speakers: speakers,
                                                      glossary: glossary),
                    generating: FinalSummary.self).content
            }
        } catch {
            guard Self.isContextWindowError(error), digests.count > 1, depth < 4 else { throw error }
            log?.event("reduce 컨텍스트 초과 — 구간 \(digests.count)개를 절반으로 압축")
            let mid = digests.count / 2
            let first = try await compress(Array(digests[..<mid]), speakers: speakers,
                                           log: log, onNotice: onNotice)
            let second = try await compress(Array(digests[mid...]), speakers: speakers,
                                            log: log, onNotice: onNotice)
            return try await finalize(digests: [first, second],
                                      speakers: speakers,
                                      log: log,
                                      onNotice: onNotice,
                                      depth: depth + 1)
        }
    }

    private func compress(_ digests: [ChunkDigest],
                          speakers: [String],
                          log: SummaryRunLog? = nil,
                          onNotice: (String?) -> Void = { _ in }) async throws -> ChunkDigest {
        try await withRateLimitRetry("compress", log: log, onNotice: onNotice) {
            let session = LanguageModelSession(instructions: SummaryTemplates.mapInstructions)
            return try await session.respond(
                to: SummaryTemplates.compressPrompt(digests: digests, speakers: speakers,
                                                    glossary: glossary),
                generating: ChunkDigest.self).content
        }
    }

    // MARK: - 실패 원인

    static func isContextWindowError(_ error: Error) -> Bool {
        if let generation = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generation {
            return true
        }
        return false
    }

    /// 요청 빈도 제한 — 실제 메시지는 "Request has been rate limited."라 공백 있는 표기도 함께 본다.
    /// 붙여 쓴 "ratelimit"만 찾다가 이 에러를 놓쳐 일반 실패 문구가 나갔다 (#21).
    static func isRateLimitError(_ error: Error) -> Bool {
        let raw = String(describing: error).lowercased()
        return raw.contains("rate limit") || raw.contains("ratelimit")
    }

    /// 사용자에게 보여줄 실패 사유 한 줄.
    /// GenerationError 케이스명은 SDK 버전을 타서, 컨텍스트 초과만 타입으로 판별하고
    /// 나머지는 에러 설명 문자열로 가른다.
    static func failureMessage(for error: Error) -> String {
        if isContextWindowError(error) {
            return "회의가 너무 길어 한 번에 요약하지 못했어요."
        }
        if isRateLimitError(error) {
            // 여기까지 만든 구간 요지는 저장돼 있어 다시 시도하면 이어서 진행된다
            return "요청이 몰려 잠시 멈췄어요. 다시 시도하면 멈춘 곳부터 이어서 해요."
        }
        let raw = String(describing: error).lowercased()
        if raw.contains("guardrail") {
            return "안전 필터에 걸려 요약을 만들지 못했어요."
        }
        if raw.contains("unsupportedlanguage") || raw.contains("locale") {
            return "지원하지 않는 언어가 섞여 있어 요약하지 못했어요."
        }
        if raw.contains("decoding") || raw.contains("unsupportedguide") {
            return "요약 결과 형식이 어긋나 읽지 못했어요."
        }
        if raw.contains("assetsunavailable") || raw.contains("modelnotready") {
            return "온디바이스 모델을 아직 내려받지 못했어요."
        }
        if raw.contains("concurrent") {
            return "다른 요약이 진행 중이에요."
        }
        if raw.contains("refus") {
            return "모델이 이 내용의 요약을 거부했어요."
        }
        if raw.contains("cancel") {
            return "요약이 중간에 멈췄어요."
        }
        return "요약 중 문제가 생겼어요."
    }

    /// 진단 로그에 남길 원본 에러 — 너무 길면 잘라 둔다
    static func errorDetail(_ error: Error) -> String {
        String(String(describing: error).prefix(300))
    }
}

/// 요약 한 번 동안의 모델 호출 속도 조절기 (#21).
///
/// 긴 회의는 모델을 스무 번 가까이 연달아 부르는데, 쉬지 않고 몰아치면 중간에 요청 제한이
/// 걸린다. 제한에 걸리기 전까지는 그대로 달리고, 한 번 걸린 뒤부터는 호출 사이에 간격을
/// 두어 남은 구간이 같은 벽에 다시 부딪히지 않게 한다.
/// map 루프가 메인 액터 밖에서 도는 구간이 있어 잠금으로 보호한다.
final class RequestPacer: @unchecked Sendable {
    /// 제한에 걸릴 때마다 올라가는 간격(초). 마지막 값에서 멈춘다.
    static let gapLadder = [0, 5, 12, 20]

    private let lock = NSLock()
    private var step = 0

    var gapSeconds: Int {
        lock.lock(); defer { lock.unlock() }
        return Self.gapLadder[step]
    }

    /// 다음 호출 전에 정해진 만큼 쉰다
    func pace() async throws {
        let gap = gapSeconds
        guard gap > 0 else { return }
        try await Task.sleep(for: .seconds(gap))
    }

    func slowDown() {
        lock.lock(); defer { lock.unlock() }
        step = min(step + 1, Self.gapLadder.count - 1)
    }
}

/// map 진행 상황. 전부 끝났으면 재요약에서 map을 통째로 건너뛰는 캐시가 되고,
/// 중간에 멈췄으면 다음 시도가 이어받는 이어달리기 지점이 된다 (#21).
struct DigestCheckpoint: Codable {
    /// 전사를 나눈 전체 구간 수 — 전사가 바뀌면 구간 경계가 달라져 이어받을 수 없다
    var chunkCount: Int
    /// 여기까지 끝냈다
    var completedChunks: Int
    var digests: [ChunkDigest]

    var isComplete: Bool { chunkCount > 0 && completedChunks >= chunkCount }
}

/// map 산출물 저장 — 템플릿 변경 시 reduce만 재실행하기 위한 캐시이자 중단 지점.
/// 처리 성공 후에도 유지되고, 회의 삭제 시 디렉터리째 지워진다.
enum DigestStore {
    /// v2는 구간 배열만 담아 어디까지 했는지 알 수 없었다. 진행 상황을 함께 적으며 v3로 올렸고,
    /// 회의록 템플릿 개편으로 ChunkDigest 모양이 바뀌어 v4가 됐다 (#21).
    /// 파일명을 올리지 않으면 예전 캐시가 새 구조로 디코딩되지 않아 매번 map을 다시 돈다.
    private static func url(meetingID: UUID) -> URL {
        AudioFileStore.directory(for: meetingID).appendingPathComponent("digests-v4.json")
    }

    static func save(_ checkpoint: DigestCheckpoint, meetingID: UUID) throws {
        let dir = AudioFileStore.directory(for: meetingID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(checkpoint).write(to: url(meetingID: meetingID), options: .atomic)
    }

    static func load(meetingID: UUID) -> DigestCheckpoint? {
        guard let data = try? Data(contentsOf: url(meetingID: meetingID)) else { return nil }
        return try? JSONDecoder().decode(DigestCheckpoint.self, from: data)
    }
}
