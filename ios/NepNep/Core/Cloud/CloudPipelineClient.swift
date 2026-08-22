import Foundation

/// 클라우드 파이프라인 서버 클라이언트 (07-m5 §3, F9)
/// 구독 검증 → 세션 토큰(24h) → Blob 직접 업로드 → RTZR 제출·폴링 → Claude 요약.
@MainActor
@Observable
final class CloudPipelineClient {
    static let shared = CloudPipelineClient()
    static let serverBaseURL = NotionAuthService.serverBaseURL
    private static let blobUploadBase = URL(string: "https://blob.vercel-storage.com")!

    private var sessionToken: String?
    private var sessionExpiry: Date = .distantPast

    enum CloudError: LocalizedError {
        case notSubscribed
        case quotaExceeded
        case jobFailed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notSubscribed: return "프로 구독이 확인되지 않았어요."
            case .quotaExceeded: return "이번 달 클라우드 시간을 다 썼어요."
            case .jobFailed: return "클라우드 처리에 실패했어요."
            case .server(let message): return message
            }
        }
    }

    // MARK: - 구독 검증 → 세션 토큰

    private struct VerifyResponse: Decodable {
        let active: Bool
        let usedSeconds: Double?
        let limitSeconds: Double?
        let sessionToken: String?
    }

    /// 유효한 세션 토큰 반환 (필요 시 verify 호출). 사용량도 함께 갱신된다.
    func validSessionToken() async throws -> String {
        if let token = sessionToken, sessionExpiry > .now { return token }
        guard let jws = await PurchaseService.shared.currentJWS() else {
            throw CloudError.notSubscribed
        }
        let response: VerifyResponse = try await post(
            path: "v1/subscription/verify",
            body: ["signedTransaction": jws])
        guard response.active, let token = response.sessionToken else {
            throw CloudError.notSubscribed
        }
        sessionToken = token
        sessionExpiry = .now.addingTimeInterval(23 * 3600)
        if let used = response.usedSeconds {
            UsageTracker.shared.usedSeconds = used
        }
        return token
    }

    /// 설정 화면 진입 시 사용량 새로고침 (1h)
    func refreshUsage() async {
        sessionExpiry = .distantPast   // verify를 강제해 최신 사용량을 받는다
        _ = try? await validSessionToken()
    }

    // MARK: - Blob 직접 업로드 (Vercel 4.5MB body 제한 대응)

    private struct UploadTicket: Decodable {
        let token: String
        let pathname: String
    }

    private struct BlobPutResponse: Decodable {
        let url: String
    }

    /// m4a 업로드 → blob URL
    func uploadAudio(fileURL: URL) async throws -> String {
        let session = try await validSessionToken()
        let ticket: UploadTicket = try await post(
            path: "v1/cloud/upload-token",
            body: ["fileName": fileURL.lastPathComponent],
            bearer: session)

        var request = URLRequest(url: Self.blobUploadBase.appendingPathComponent(ticket.pathname))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(ticket.token)", forHTTPHeaderField: "Authorization")
        request.setValue("7", forHTTPHeaderField: "x-api-version")
        request.setValue("audio/mp4", forHTTPHeaderField: "x-content-type")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CloudError.server("오디오 업로드에 실패했어요 (\(String(data: data, encoding: .utf8) ?? ""))")
        }
        return try JSONDecoder().decode(BlobPutResponse.self, from: data).url
    }

    // MARK: - 전사 제출·폴링

    private struct SubmitResponse: Decodable { let jobId: String }
    private struct SubmitRequest: Encodable {
        let blobUrl: String
        let durationSec: Double
    }

    func submitTranscription(blobUrl: String, durationSec: Double) async throws -> String {
        let session = try await validSessionToken()
        let response: SubmitResponse = try await post(
            path: "v1/cloud/transcribe",
            body: SubmitRequest(blobUrl: blobUrl, durationSec: durationSec),
            bearer: session)
        return response.jobId
    }

    struct CloudUtterance: Decodable {
        let start_at: Int    // ms
        let duration: Int    // ms
        let msg: String
        let spk: Int
    }

    enum PollResult {
        case pending
        case completed([CloudUtterance])
    }

    private struct PollResponse: Decodable {
        let status: String
        let utterances: [CloudUtterance]?
    }

    func poll(jobId: String, blobUrl: String, durationSec: Double) async throws -> PollResult {
        let session = try await validSessionToken()
        var components = URLComponents(
            url: Self.serverBaseURL.appendingPathComponent("v1/cloud/transcribe/\(jobId)"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "blobUrl", value: blobUrl),
            URLQueryItem(name: "durationSec", value: String(Int(durationSec.rounded(.up)))),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response: response, data: data)
        let poll = try JSONDecoder().decode(PollResponse.self, from: data)
        switch poll.status {
        case "completed": return .completed(poll.utterances ?? [])
        case "failed": throw CloudError.jobFailed
        default: return .pending
        }
    }

    // MARK: - 요약

    struct CloudSummary: Decodable {
        let oneLiner: String
        let keyPoints: [String]
        let decisions: [String]
        let actionItems: [String]
    }

    func summarize(transcript: String, meetingTypeName: String) async throws -> CloudSummary {
        let session = try await validSessionToken()
        return try await post(
            path: "v1/cloud/summarize",
            body: ["transcript": transcript, "meetingTypeName": meetingTypeName],
            bearer: session)
    }

    // MARK: - 공통

    private func post<Body: Encodable, Response: Decodable>(
        path: String, body: Body, bearer: String? = nil) async throws -> Response {
        var request = URLRequest(url: Self.serverBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func checkStatus(response: URLResponse, data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw CloudError.server("서버 응답이 올바르지 않아요.")
        }
        switch status {
        case 200...299: return
        case 402: throw CloudError.quotaExceeded
        case 401: throw CloudError.notSubscribed
        default:
            struct ErrorBody: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw CloudError.server(message ?? "서버 오류 (\(status))")
        }
    }
}

/// 클라우드 작업 체크포인트 — 앱 종료 후 재실행 시 jobId 폴링 재개 (07-m5 §3)
struct CloudJobCheckpoint: Codable {
    var jobId: String
    var blobUrl: String
    var durationSec: Double

    private static func url(meetingID: UUID) -> URL {
        AudioFileStore.directory(for: meetingID).appendingPathComponent("cloud-job.json")
    }

    func save(meetingID: UUID) {
        let url = Self.url(meetingID: meetingID)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func load(meetingID: UUID) -> CloudJobCheckpoint? {
        guard let data = try? Data(contentsOf: url(meetingID: meetingID)) else { return nil }
        return try? JSONDecoder().decode(CloudJobCheckpoint.self, from: data)
    }

    static func clear(meetingID: UUID) {
        try? FileManager.default.removeItem(at: url(meetingID: meetingID))
    }
}
