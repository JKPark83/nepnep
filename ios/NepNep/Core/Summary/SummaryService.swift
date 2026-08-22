import Foundation
import FoundationModels
import SwiftData

/// Foundation Models map-reduce 요약 오케스트레이션 (05-m3 §4)
///
/// [Utterance…] → Chunker → 청크별 세션(ChunkDigest)     // map (순차 — 발열 고려)
///              → digests 병합 → 새 세션(FinalSummary)    // reduce (템플릿 instructions)
///              → 한도 초과 시 digest 압축 후 2단 reduce
struct SummaryService {
    /// 온디바이스 모델 가용 여부 — 비가용 시 요약을 건너뛴다 (처리 전체는 성공)
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - 전체 파이프라인

    /// digests 저장본이 있으면 map을 생략하고 reduce만 재실행한다 (템플릿 변경 재요약, 05-m3 §5)
    @MainActor
    static func generate(meeting: Meeting,
                         type: MeetingType,
                         context: ModelContext,
                         onProgress: @escaping (Double) -> Void = { _ in }) async throws {
        let service = SummaryService()
        let digests: [ChunkDigest]
        if let saved = DigestStore.load(meetingID: meeting.id), !saved.isEmpty {
            digests = saved
            onProgress(0.9)
        } else {
            let lines = transcriptLines(meeting: meeting)
            guard !lines.isEmpty else { return }
            digests = try await service.makeDigests(lines: lines) { p in
                onProgress(p * 0.9)   // map 0~0.9, reduce 0.9~1
            }
            try? DigestStore.save(digests, meetingID: meeting.id)
        }
        let final = try await service.finalize(digests: digests, type: type)
        apply(final, to: meeting, type: type, context: context)
        onProgress(1)
    }

    @MainActor
    static func transcriptLines(meeting: Meeting) -> [String] {
        let names = Dictionary(uniqueKeysWithValues: meeting.speakers.map { ($0.id, $0.displayName) })
        return meeting.utterances
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { "\(names[$0.speakerID] ?? "화자"): \($0.text)" }
    }

    /// FinalSummary → Summary/TodoItem 반영 (기존 요약 교체)
    @MainActor
    static func apply(_ final: FinalSummary,
                      to meeting: Meeting,
                      type: MeetingType,
                      context: ModelContext) {
        if let old = meeting.summary {
            meeting.summary = nil
            context.delete(old)
        }
        let template = SummaryTemplates.template(for: type)
        let sections = [
            SummarySection(title: template.keyPointsTitle, bullets: final.keyPoints),
            SummarySection(title: template.decisionsTitle, bullets: final.decisions),
        ].filter { !$0.bullets.isEmpty }

        let summary = Summary(templateTypeRaw: type.rawValue,
                              oneLiner: final.oneLiner,
                              sections: sections)
        meeting.summary = summary
        for (i, raw) in final.actionItems.enumerated() {
            guard let parsed = SummaryTemplates.parseActionItem(raw) else { continue }
            summary.todos.append(TodoItem(text: parsed.text,
                                          assignee: parsed.assignee,
                                          due: parsed.due,
                                          orderIndex: i))
        }
        // 자동 제목이면 요약이 뽑은 주제로 교체 — 사용자가 바꾼 제목은 건드리지 않는다
        if Meeting.isAutoTitle(meeting.title, date: meeting.createdAt),
           let generated = Meeting.summaryTitle(topic: final.title, date: meeting.createdAt) {
            meeting.title = generated
        }
        meeting.type = type
        meeting.summaryUnavailable = false
        try? context.save()
    }

    // MARK: - map

    func makeDigests(lines: [String],
                     onProgress: (Double) -> Void = { _ in }) async throws -> [ChunkDigest] {
        let chunks = TranscriptChunker.chunk(lines)
        var digests: [ChunkDigest] = []
        for (i, chunk) in chunks.enumerated() {
            digests.append(contentsOf: try await digest(chunkText: chunk, depth: 0))
            onProgress(Double(i + 1) / Double(max(chunks.count, 1)))
        }
        return digests
    }

    /// 컨텍스트 한도 초과 시 청크를 반으로 재분할해 재시도 (05-m3 §4)
    private func digest(chunkText: String, depth: Int) async throws -> [ChunkDigest] {
        do {
            let session = LanguageModelSession(instructions: SummaryTemplates.mapInstructions)
            let response = try await session.respond(
                to: SummaryTemplates.mapPrompt(chunkText: chunkText),
                generating: ChunkDigest.self)
            return [response.content]
        } catch {
            guard Self.isContextWindowError(error), depth < 3, chunkText.count > 200 else {
                throw error
            }
            let lines = chunkText.split(separator: "\n").map(String.init)
            let halves = TranscriptChunker.chunk(lines, limit: max(200, chunkText.count / 2))
            var result: [ChunkDigest] = []
            for half in halves {
                result.append(contentsOf: try await digest(chunkText: half, depth: depth + 1))
            }
            return result
        }
    }

    // MARK: - reduce

    func finalize(digests: [ChunkDigest], type: MeetingType) async throws -> FinalSummary {
        let template = SummaryTemplates.template(for: type)
        do {
            let session = LanguageModelSession(instructions: template.instructions)
            let response = try await session.respond(
                to: SummaryTemplates.reducePrompt(digests: digests),
                generating: FinalSummary.self)
            return response.content
        } catch {
            guard Self.isContextWindowError(error), digests.count > 1 else { throw error }
            // 2단 reduce: digest들을 절반씩 압축한 뒤 다시 최종 요약
            let mid = digests.count / 2
            let first = try await compress(Array(digests[..<mid]))
            let second = try await compress(Array(digests[mid...]))
            return try await finalize(digests: [first, second], type: type)
        }
    }

    private func compress(_ digests: [ChunkDigest]) async throws -> ChunkDigest {
        let session = LanguageModelSession(instructions: SummaryTemplates.mapInstructions)
        let prompt = SummaryTemplates.reducePrompt(digests: digests)
            + "\n\n위 구간 요지들을 중복 없이 더 압축해 정리하세요."
        return try await session.respond(to: prompt, generating: ChunkDigest.self).content
    }

    private static func isContextWindowError(_ error: Error) -> Bool {
        if let generation = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generation {
            return true
        }
        return false
    }
}

/// map 산출물(digests.json) 저장 — 템플릿 변경 시 reduce만 재실행하기 위한 캐시.
/// 체크포인트와 달리 처리 성공 후에도 유지되고, 회의 삭제 시 디렉터리째 지워진다.
enum DigestStore {
    private static func url(meetingID: UUID) -> URL {
        AudioFileStore.directory(for: meetingID).appendingPathComponent("digests.json")
    }

    static func save(_ digests: [ChunkDigest], meetingID: UUID) throws {
        let dir = AudioFileStore.directory(for: meetingID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(digests).write(to: url(meetingID: meetingID), options: .atomic)
    }

    static func load(meetingID: UUID) -> [ChunkDigest]? {
        guard let data = try? Data(contentsOf: url(meetingID: meetingID)) else { return nil }
        return try? JSONDecoder().decode([ChunkDigest].self, from: data)
    }
}
