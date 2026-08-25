import Foundation

/// 파이프라인 공용 타입 + 엔진 프로토콜 (03-m2 §1)

/// 어떤 엔진이 만든 결과인지 (체크포인트에 기록된다).
///
/// 원래 enum이었는데 원격 서버가 붙으면서 값이 engines.yml에서 온다 — 코드에
/// 미리 적어 둘 수 없다. rawValue 문자열로 인코딩되므로 예전에 저장된
/// 체크포인트도 그대로 읽힌다.
struct EngineID: RawRepresentable, Codable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    static let speechTranscriber = EngineID("speechTranscriber")
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

    /// progress가 실제로 차오르는가.
    ///
    /// 원격 엔진은 올리는 동안만 알 수 있고 서버가 도는 몇 분은 알 길이 없다.
    /// 그때 퍼센트를 보여주면 절반에서 멈춘 것처럼 보이므로, 화면이 스피너로
    /// 바꿔 달 수 있게 알려 준다.
    var reportsProgress: Bool { get }
}

extension TranscriptionEngine {
    var reportsProgress: Bool { true }
}

protocol DiarizationProviding {
    func diarize(url: URL) async throws -> [SpeakerSegment]
}

/// 파이프라인 실패 원인 (03-m2 §4)
enum ProcessingFailureReason: String, Codable {
    case assetMissing   // 선택 엔진 모델 미설치
    case diskFull
    case engineError
}
