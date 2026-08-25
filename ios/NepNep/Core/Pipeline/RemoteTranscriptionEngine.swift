import AVFoundation
import Foundation

/// 원격 서버에 오디오를 올려 전사를 받아 오는 엔진 (#21 후속).
///
/// 규격이 둘이다. 대부분은 OpenAI의 `/v1/audio/transcriptions`를 그대로 쓰므로
/// (맥미니에 띄운 Whisper 서버, OpenAI, Groq) 주소만 다른 같은 코드로 처리하고,
/// Deepgram만 `/v1/listen`이라 갈라 둔다.
///
/// 올릴 때는 녹음 원본(CAF, 16kHz PCM)이 아니라 m4a로 줄여 보낸다. 48분 회의가
/// 93MB에서 12MB가 된다 — 전사기에 들어가는 소리는 어차피 같은 16kHz다.
///
/// 넵넵 서버(`jobs: true`)에는 맡겨 두고 나중에 찾아간다. 한 연결로 끝까지
/// 기다리면 앱이 백그라운드로 내려가는 순간 iOS가 앱을 재우면서 소켓이 끊겨
/// "-1005"가 뜬다 — 몇 분씩 걸리는 긴 회의에서 실제로 그랬다.
final class RemoteTranscriptionEngine: NSObject, TranscriptionEngine {
    let descriptor: EngineDescriptor

    /// Deepgram처럼 서버가 화자분리까지 해 주는 경우, 전사 응답에 실려 온 화자
    /// 구간을 여기 담아 둔다. 같은 파일을 두 번 올리지 않으려는 것이다.
    private var cachedSegments: [SpeakerSegment]?
    private var cachedSegmentsURL: URL?

    /// 업로드 진행률을 밖으로 흘리는 통로 (URLSession 델리게이트가 쓴다)
    private var onUploadProgress: ((Double) -> Void)?

    init(descriptor: EngineDescriptor) {
        self.descriptor = descriptor
        super.init()
    }

    var id: EngineID { descriptor.engineID }

    /// 올리는 동안은 진짜 진행률을 알지만 서버가 도는 동안은 모른다.
    /// 절반에서 멈춘 막대를 보여주느니 화면이 스피너를 돌리게 둔다.
    var reportsProgress: Bool { false }

    enum RemoteError: LocalizedError {
        case missingAPIKey(String)
        case badStatus(Int, String)
        case badResponse
        case noWords

        var errorDescription: String? {
            switch self {
            case .missingAPIKey(let name):
                return "\(name) API 키가 없습니다. 설정 > 전사 엔진에서 넣어 주세요."
            case .badStatus(let code, let body):
                return "서버가 \(code)로 답했습니다. \(body.prefix(200))"
            case .badResponse:
                return "서버 응답을 읽지 못했습니다."
            case .noWords:
                return "서버가 빈 전사를 돌려줬습니다."
            }
        }
    }

    // MARK: - 준비 확인

    /// 서버가 살아 있는지. 키가 필요한데 없으면 올려 보기 전에 먼저 걸러낸다.
    func isReady() async -> Bool {
        if descriptor.needsAPIKey, apiKey() == nil { return false }
        do {
            _ = try await probe()
            return true
        } catch {
            return false
        }
    }

    /// 설정 화면의 "연결 확인" — 실패 이유를 그대로 보여줘야 해서 던진다.
    func probe() async throws {
        var request = URLRequest(url: healthURL())
        request.timeoutInterval = 10
        try authorize(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteError.badResponse }
        // 목록·헬스 경로는 서비스마다 달라서 200이 아니어도 인증만 통과하면 살아 있다고 본다.
        guard http.statusCode != 401, http.statusCode != 403 else {
            throw RemoteError.badStatus(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: - 전사

    func transcribe(url: URL,
                    progress: @escaping (Double) -> Void) async throws -> [TranscriptWord] {
        if descriptor.needsAPIKey, apiKey() == nil {
            throw RemoteError.missingAPIKey(descriptor.name)
        }

        // 만들어 쓴 임시 파일만 지운다 — 녹음 원본을 지우면 재처리 길이 막힌다.
        var scratch: [URL] = []
        defer { scratch.forEach { try? FileManager.default.removeItem(at: $0) } }

        let audio = try await compressedCopy(of: url)
        if audio != url { scratch.append(audio) }
        let body = try bodyFile(for: audio)
        if body != audio { scratch.append(body) }

        // 올리는 동안은 진짜 진행률을 그대로 흘린다. 다 올리고 나면 서버가 도는
        // 동안은 알 길이 없으므로 더 안 건드린다 — 화면은 reportsProgress를 보고
        // 그때부터 스피너로 바꿔 단다.
        onUploadProgress = progress
        defer { onUploadProgress = nil }

        let data: Data
        if await usesJobAPI() {
            data = try await runJob(uploading: body)
        } else {
            let (payload, response) = try await urlSession.upload(
                for: try buildRequest(),
                fromFile: body,
                delegate: self)
            try Self.check(response, payload)
            data = payload
        }

        let parsed: (words: [TranscriptWord], segments: [SpeakerSegment]?)
        switch descriptor.kind {
        case .deepgram: parsed = try Self.parseDeepgram(data)
        case .openAI, .onDevice: parsed = (try Self.parseOpenAI(data), nil)
        }

        guard !parsed.words.isEmpty else { throw RemoteError.noWords }
        cachedSegments = parsed.segments
        cachedSegmentsURL = url
        progress(1)
        return parsed.words
    }

    // MARK: - 맡기고 찾아가기

    /// 이 서버에 맡겨 둘 수 있는가. YAML보다 서버에 물어본 답을 먼저 믿는다.
    ///
    /// engines.yml의 `jobs: true`만 보고 정했더니, 파일 앱에서 목록을 한 번
    /// 복사해 둔 사람은 앱을 업데이트해도 그 옛 파일이 번들 기본값을 이겨서
    /// 계속 옛 경로로 갔다 — 백그라운드에 다녀오면 여전히 -1005였다. 서버 기능은
    /// 설정 파일이 아니라 서버가 알고 있다.
    private func usesJobAPI() async -> Bool {
        if descriptor.usesJobAPI { return true }
        guard descriptor.kind == .openAI else { return false }
        if let detectedJobSupport { return detectedJobSupport }
        let detected = await detectJobSupport()
        detectedJobSupport = detected
        return detected
    }

    private var detectedJobSupport: Bool?

    /// `/health`가 작업 수를 세어 주면 넵넵 서버다. 남의 서버는 이 경로가 없다.
    private func detectJobSupport() async -> Bool {
        guard let base = descriptor.baseURL else { return false }
        var request = URLRequest(url: base.appending(path: "health"))
        request.timeoutInterval = 5
        try? authorize(&request)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return Self.serverKnowsJobs(data)
    }

    /// `/health` 본문에 작업 수가 세어져 있으면 넵넵 서버다.
    static func serverKnowsJobs(_ data: Data) -> Bool {
        struct Health: Decodable { let jobs: Int? }
        return (try? JSONDecoder().decode(Health.self, from: data))?.jobs != nil
    }

    /// 물어보는 간격. 전사가 몇 분짜리라 자주 찌를 이유가 없다.
    private static let pollInterval: Duration = .seconds(3)
    /// 물어보는 요청 하나에 주는 시간. 올릴 때(10분)와 달리 짧아야 한다 —
    /// 답이 안 오면 다시 물어보면 그만이다.
    private static let pollTimeout: TimeInterval = 30
    /// 이때까지도 안 끝났으면 서버에 무슨 일이 난 것으로 본다.
    private static let jobDeadline: TimeInterval = 3600
    /// 앱이 백그라운드에 있는 동안은 요청이 통째로 실패한다. 연달아 이만큼
    /// 실패해야 진짜 포기한다 — 한 번 실패했다고 놓으면 잠깐 나갔다 온 것만으로 끝난다.
    private static let pollFailureLimit = 20

    private func runJob(uploading body: URL) async throws -> Data {
        var request = try openAIRequest(path: "v1/jobs")
        request.timeoutInterval = Self.requestTimeout
        let (data, response) = try await urlSession.upload(
            for: request, fromFile: body, delegate: self)
        try Self.check(response, data)

        struct Handle: Decodable { let id: String }
        guard let handle = try? JSONDecoder().decode(Handle.self, from: data) else {
            throw RemoteError.badResponse
        }
        return try await poll(jobID: handle.id)
    }

    private func poll(jobID: String) async throws -> Data {
        let url = descriptor.baseURL!.appending(path: "v1/jobs/\(jobID)")
        let deadline = Date().addingTimeInterval(Self.jobDeadline)
        var failures = 0

        while Date() < deadline {
            try await Task.sleep(for: Self.pollInterval)
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = Self.pollTimeout
                try authorize(&request)
                let (data, response) = try await urlSession.data(for: request)
                try Self.check(response, data)   // 404면 만료됐거나 서버가 다시 떴다
                failures = 0
                switch try Self.parseJobState(data) {
                case .running: continue
                case .done: return data
                case .failed(let message): throw RemoteError.badStatus(200, message)
                }
            } catch let error as RemoteError {
                throw error   // 서버가 답을 준 실패다. 다시 물어봐도 같은 답이 온다.
            } catch {
                failures += 1
                if failures > Self.pollFailureLimit { throw error }
            }
        }
        throw RemoteError.badStatus(408, "서버가 한 시간이 넘도록 끝내지 못했습니다.")
    }

    enum JobState: Equatable {
        case running
        case done
        case failed(String)
    }

    /// 맡긴 작업의 상태. 끝난 결과는 감싸지 않고 그대로 실려 오므로 여기서는
    /// status만 보고, 본문은 호출 측이 `parseOpenAI`로 읽는다.
    static func parseJobState(_ data: Data) throws -> JobState {
        struct Payload: Decodable {
            struct Failure: Decodable { let message: String }
            let status: String?
            let error: Failure?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw RemoteError.badResponse
        }
        switch payload.status {
        case "running": return .running
        case "done": return .done
        case "failed": return .failed(payload.error?.message ?? "서버가 이유를 말하지 않았습니다.")
        default: throw RemoteError.badResponse
        }
    }

    // MARK: - 요청 만들기

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw RemoteError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteError.badStatus(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    private func healthURL() -> URL {
        guard let base = descriptor.baseURL else { return URL(string: "http://127.0.0.1")! }
        switch descriptor.kind {
        case .deepgram: return base.appending(path: "v1/projects")
        case .openAI, .onDevice: return base.appending(path: "v1/models")
        }
    }

    private func apiKey() -> String? {
        guard let ref = descriptor.apiKeyRef, !ref.isEmpty else { return nil }
        return EngineKeychain.key(for: ref)
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard descriptor.needsAPIKey else { return }
        guard let key = apiKey() else { throw RemoteError.missingAPIKey(descriptor.name) }
        switch descriptor.kind {
        case .deepgram:
            request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        case .openAI, .onDevice:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    /// 세션은 엔진과 수명을 같이 한다 — 요청마다 새로 만들어 붙들지 않으면
    /// 응답을 기다리는 중에 세션이 풀려 연결이 끊긴다.
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    /// 긴 회의는 서버가 몇 분씩 붙잡고 있는다. 48분짜리가 2분 40초였으니
    /// 넉넉히 10분을 준다.
    private static let requestTimeout: TimeInterval = 600

    private func buildRequest() throws -> URLRequest {
        var request: URLRequest
        switch descriptor.kind {
        case .deepgram: request = try deepgramRequest()
        case .openAI, .onDevice: request = try openAIRequest(path: "v1/audio/transcriptions")
        }
        // URLRequest 자신의 기본 60초가 세션 설정을 이긴다. 여기서 안 덮으면
        // 긴 회의는 서버가 아직 도는 중에 클라이언트가 먼저 포기한다.
        request.timeoutInterval = Self.requestTimeout
        return request
    }

    private var multipartBoundary: String { "nepnep-\(descriptor.id)-boundary" }

    private func openAIRequest(path: String) throws -> URLRequest {
        var request = URLRequest(url: descriptor.baseURL!.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(multipartBoundary)",
                         forHTTPHeaderField: "Content-Type")
        try authorize(&request)
        return request
    }

    private func deepgramRequest() throws -> URLRequest {
        var components = URLComponents(
            url: descriptor.baseURL!.appending(path: "v1/listen"),
            resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
        ]
        if let model = descriptor.model { items.append(.init(name: "model", value: model)) }
        if let language = descriptor.language {
            items.append(.init(name: "language", value: language))
        }
        if descriptor.diarizes { items.append(.init(name: "diarize", value: "true")) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        try authorize(&request)
        return request
    }

    /// 업로드 본문을 파일로 만들어 둔다 — 메모리에 통째로 올리지 않으려는 것이다.
    private func bodyFile(for audio: URL) throws -> URL {
        guard descriptor.kind != .deepgram else { return audio }   // Deepgram은 원본 그대로

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        func field(_ name: String, _ value: String) -> String {
            "--\(multipartBoundary)\r\n"
                + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }

        var head = ""
        if let model = descriptor.model { head += field("model", model) }
        if let language = descriptor.language { head += field("language", language) }
        head += field("response_format", "verbose_json")
        // 단어 타임스탬프가 있어야 화자분리 결과와 붙일 수 있다.
        head += field("timestamp_granularities[]", "word")
        head += "--\(multipartBoundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(audio.lastPathComponent)\"\r\n"
            + "Content-Type: audio/mp4\r\n\r\n"
        try handle.write(contentsOf: Data(head.utf8))

        let input = try FileHandle(forReadingFrom: audio)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
        try handle.write(contentsOf: Data("\r\n--\(multipartBoundary)--\r\n".utf8))
        return destination
    }

    /// CAF 원본을 m4a로 줄인 임시 사본. 이미 m4a면 그대로 쓴다.
    private func compressedCopy(of url: URL) async throws -> URL {
        guard url.pathExtension.lowercased() == "caf" else { return url }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).m4a")
        try await AudioTranscoder.transcode(caf: url, to: destination)
        return destination
    }

    // MARK: - 응답 읽기

    /// OpenAI `verbose_json` — 최상위 words[]를 먼저 보고, 없으면 구간 안의 words[]를 본다.
    static func parseOpenAI(_ data: Data) throws -> [TranscriptWord] {
        struct Word: Decodable {
            let word: String
            let start: TimeInterval
            let end: TimeInterval
            let probability: Double?
        }
        struct Segment: Decodable {
            let text: String?
            let start: TimeInterval
            let end: TimeInterval
            let words: [Word]?
        }
        struct ServerError: Decodable {
            struct Body: Decodable { let message: String }
            let error: Body
        }
        struct Payload: Decodable {
            let text: String?
            let words: [Word]?
            let segments: [Segment]?
        }

        // 서버가 스트리밍으로 답하기 시작한 뒤에는 상태 코드로 실패를 알릴 수
        // 없다. 본문에 실려 온 이유를 그대로 올려 준다.
        if let failure = try? JSONDecoder().decode(ServerError.self, from: data) {
            throw RemoteError.badStatus(200, failure.error.message)
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw RemoteError.badResponse
        }

        let words = payload.words ?? payload.segments?.compactMap(\.words).flatMap { $0 }
        if let words, !words.isEmpty {
            return words.map {
                TranscriptWord(text: $0.word, start: $0.start, end: $0.end,
                               confidence: $0.probability ?? 1)
            }
        }
        // 단어 타임스탬프를 안 주는 서버도 있다. 구간 단위로라도 받아 둔다.
        if let segments = payload.segments, !segments.isEmpty {
            return segments.map {
                TranscriptWord(text: $0.text ?? "", start: $0.start, end: $0.end, confidence: 1)
            }
        }
        // 타임스탬프가 아예 없으면 화자분리와 붙일 수 없다 — -1로 두면
        // TranscriptMerger가 시간 없는 조각으로 다룬다.
        if let text = payload.text, !text.isEmpty {
            return [TranscriptWord(text: text, start: -1, end: -1, confidence: 1)]
        }
        return []
    }

    /// Deepgram `/v1/listen` — 단어마다 화자 번호가 붙어 오므로 화자 구간도 같이 만든다.
    static func parseDeepgram(_ data: Data) throws -> ([TranscriptWord], [SpeakerSegment]?) {
        struct Word: Decodable {
            let word: String
            let punctuated_word: String?
            let start: TimeInterval
            let end: TimeInterval
            let confidence: Double?
            let speaker: Int?
        }
        struct Alternative: Decodable { let words: [Word]? }
        struct Channel: Decodable { let alternatives: [Alternative]? }
        struct Results: Decodable { let channels: [Channel]? }
        struct Payload: Decodable { let results: Results? }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let raw = payload.results?.channels?.first?.alternatives?.first?.words else {
            throw RemoteError.badResponse
        }

        let words = raw.map {
            TranscriptWord(text: ($0.punctuated_word ?? $0.word) + " ",
                           start: $0.start, end: $0.end,
                           confidence: $0.confidence ?? 1)
        }

        // 같은 화자가 이어지는 동안을 한 구간으로 묶는다
        var segments: [SpeakerSegment] = []
        for word in raw {
            guard let speaker = word.speaker else { continue }
            let key = "speaker\(speaker)"
            if let last = segments.last, last.speakerKey == key, last.end >= word.start - 2 {
                segments[segments.count - 1] = SpeakerSegment(
                    speakerKey: key, start: last.start, end: word.end)
            } else {
                segments.append(SpeakerSegment(speakerKey: key, start: word.start, end: word.end))
            }
        }
        return (words, segments.isEmpty ? nil : segments)
    }
}

// MARK: - 업로드 진행률

extension RemoteTranscriptionEngine: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onUploadProgress?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - 서버가 해 준 화자분리

/// 서버가 화자까지 나눠 준 경우 전사 응답에 실려 온 것을 그대로 쓴다.
/// 같은 파일을 화자분리용으로 한 번 더 올리지 않기 위해서다.
extension RemoteTranscriptionEngine: DiarizationProviding {
    func diarize(url: URL) async throws -> [SpeakerSegment] {
        guard cachedSegmentsURL == url, let segments = cachedSegments else {
            // 전사가 체크포인트에서 복원돼 이 인스턴스가 응답을 못 본 경우다.
            // 기기 안 화자분리로 대신한다.
            return try await DiarizationService().diarize(url: url)
        }
        return segments
    }
}
