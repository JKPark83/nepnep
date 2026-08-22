import Foundation

/// 파이프라인 공용 타입 + 엔진 프로토콜 (03-m2 §1)

enum EngineID: String, Codable, CaseIterable {
    case speechTranscriber
}

struct TranscriptWord: Codable, Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
}

struct SpeakerSegment: Codable, Equatable {
    let speakerKey: String
    let start: TimeInterval
    let end: TimeInterval
}

protocol TranscriptionEngine {
    var id: EngineID { get }
    /// 에셋(언어 모델) 설치 여부
    func isReady() async -> Bool
    func transcribe(url: URL, progress: @escaping (Double) -> Void) async throws -> [TranscriptWord]
}

protocol DiarizationProviding {
    func diarize(url: URL) async throws -> [SpeakerSegment]
}

/// 파이프라인 실패 원인 (03-m2 §4)
enum ProcessingFailureReason: String, Codable {
    case assetMissing   // 선택 엔진 모델 미설치
    case diskFull
    case engineError
    case cloudFailed    // 클라우드 처리 실패 — 온디바이스 폴백 제안 (07-m5 F9-4)
    case quotaExceeded  // 월 클라우드 시간 소진 (07-m5 §4)
}
