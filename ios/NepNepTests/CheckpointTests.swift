import XCTest
@testable import NepNep

final class CheckpointTests: XCTestCase {
    private var dir: URL!
    private var checkpoint: ProcessingCheckpoint!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkpoint-tests-\(UUID().uuidString)")
        checkpoint = ProcessingCheckpoint(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let sampleWords = [
        TranscriptWord(text: "안녕", start: 0, end: 0.5, confidence: 0.9),
        TranscriptWord(text: "하세요", start: 0.5, end: 1.2, confidence: 0.8),
    ]
    private let sampleSegments = [
        SpeakerSegment(speakerKey: "S0", start: 0, end: 3),
    ]

    /// 라운드트립: save → load 동일성 (03-m2 §3)
    func testRoundTrip() throws {
        try checkpoint.saveWords(sampleWords, engineID: .speechTranscriber)
        try checkpoint.saveSegments(sampleSegments, engineID: .speechTranscriber)

        XCTAssertEqual(checkpoint.loadWords(), sampleWords)
        XCTAssertEqual(checkpoint.loadSegments(), sampleSegments)
        let state = checkpoint.loadState()
        XCTAssertEqual(state?.stage, .diarized)
        XCTAssertEqual(state?.engineID, .speechTranscriber)
    }

    /// clear 후에는 아무것도 남지 않는다
    func testClearRemovesEverything() throws {
        try checkpoint.saveWords(sampleWords, engineID: .speechTranscriber)
        checkpoint.clear()
        XCTAssertNil(checkpoint.loadWords())
        XCTAssertNil(checkpoint.loadState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    /// 전사 체크포인트에서 재개 시 전사는 건너뛰고 화자분리만 실행 (03-m2 §3)
    func testResumeSkipsTranscription() async throws {
        try checkpoint.saveWords(sampleWords, engineID: .speechTranscriber)

        let engine = StubEngine()
        let diarizer = StubDiarizer(segments: sampleSegments)
        let runner = PipelineRunner(engine: engine, diarizer: diarizer,
                                    checkpoint: checkpoint)
        let result = try await runner.run(audioURL: URL(fileURLWithPath: "/unused")) { _ in }

        XCTAssertEqual(engine.callCount.value, 0, "전사를 다시 돌면 안 된다")
        XCTAssertEqual(diarizer.callCount.value, 1)
        XCTAssertFalse(result.isEmpty)
    }

    /// 화자분리까지 완료된 체크포인트에서 재개 시 두 단계 모두 건너뛴다
    func testResumeSkipsBothStages() async throws {
        try checkpoint.saveWords(sampleWords, engineID: .speechTranscriber)
        try checkpoint.saveSegments(sampleSegments, engineID: .speechTranscriber)

        let engine = StubEngine()
        let diarizer = StubDiarizer(segments: [])
        let runner = PipelineRunner(engine: engine, diarizer: diarizer,
                                    checkpoint: checkpoint)
        _ = try await runner.run(audioURL: URL(fileURLWithPath: "/unused")) { _ in }

        XCTAssertEqual(engine.callCount.value, 0)
        XCTAssertEqual(diarizer.callCount.value, 0)
    }

    /// 체크포인트 없으면 두 단계 모두 실행 + 완료 후 체크포인트 존재
    func testFreshRunExecutesAllStages() async throws {
        let engine = StubEngine(words: sampleWords)
        let diarizer = StubDiarizer(segments: sampleSegments)
        let runner = PipelineRunner(engine: engine, diarizer: diarizer,
                                    checkpoint: checkpoint)
        _ = try await runner.run(audioURL: URL(fileURLWithPath: "/unused")) { _ in }

        XCTAssertEqual(engine.callCount.value, 1)
        XCTAssertEqual(diarizer.callCount.value, 1)
        XCTAssertEqual(checkpoint.loadState()?.stage, .diarized)
    }
}

// MARK: - 스텁 (호출 횟수 검증용, 03-m2 §3)

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private struct StubEngine: TranscriptionEngine {
    let id: EngineID = .speechTranscriber
    var words: [TranscriptWord] = []
    let callCount = Counter()

    func isReady() async -> Bool { true }
    func transcribe(url: URL,
                    progress: @escaping (Double) -> Void) async throws -> [TranscriptWord] {
        callCount.increment()
        return words
    }
}

private struct StubDiarizer: DiarizationProviding {
    let segments: [SpeakerSegment]
    let callCount = Counter()

    func diarize(url: URL) async throws -> [SpeakerSegment] {
        callCount.increment()
        return segments
    }
}
