import Foundation

/// 단계별 중간 산출물 저장·복원 (03-m2 §3, F10-2)
/// Application Support/audio/<meetingID>/checkpoint/{words.json, segments.json, state.json}
struct ProcessingCheckpoint {
    enum Stage: String, Codable {
        case transcribed
        case diarized
    }

    struct State: Codable {
        var stage: Stage
        var engineID: EngineID
        var updatedAt: Date
    }

    let directory: URL

    init(meetingID: UUID) {
        self.directory = AudioFileStore.directory(for: meetingID)
            .appendingPathComponent("checkpoint", isDirectory: true)
    }

    /// 테스트용 임의 디렉터리 주입
    init(directory: URL) {
        self.directory = directory
    }

    private var wordsURL: URL { directory.appendingPathComponent("words.json") }
    private var segmentsURL: URL { directory.appendingPathComponent("segments.json") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    // MARK: - 저장 (각 단계 완료 직후 원자적 write)

    func saveWords(_ words: [TranscriptWord], engineID: EngineID) throws {
        try ensureDirectory()
        try write(words, to: wordsURL)
        try write(State(stage: .transcribed, engineID: engineID, updatedAt: .now), to: stateURL)
    }

    func saveSegments(_ segments: [SpeakerSegment], engineID: EngineID) throws {
        try ensureDirectory()
        try write(segments, to: segmentsURL)
        try write(State(stage: .diarized, engineID: engineID, updatedAt: .now), to: stateURL)
    }

    // MARK: - 복원

    func loadState() -> State? {
        read(State.self, from: stateURL)
    }

    func loadWords() -> [TranscriptWord]? {
        read([TranscriptWord].self, from: wordsURL)
    }

    func loadSegments() -> [SpeakerSegment]? {
        read([SpeakerSegment].self, from: segmentsURL)
    }

    /// 전 단계 성공 후 삭제 (03-m2 §3)
    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 내부

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
