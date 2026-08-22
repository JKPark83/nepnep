import FluidAudio
import Foundation

/// FluidAudio 화자분리 래퍼 (03-m2 §1, M0 §5 코드 재사용)
struct DiarizationService: DiarizationProviding {
    /// 모델 다운로드·컴파일 (최초 설치 화면 + 프리웜 공용)
    static func downloadModels() async throws {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        try await manager.prepareModels()
    }

    /// 모델 사전 다운로드 (앱 시작 프리웜용) — 실패해도 diarize 시점에 재시도됨
    static func prewarm() async {
        try? await downloadModels()
    }

    func diarize(url: URL) async throws -> [SpeakerSegment] {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        try await manager.prepareModels()
        let result = try await manager.process(url)
        return result.segments.map {
            SpeakerSegment(speakerKey: $0.speakerId,
                           start: TimeInterval($0.startTimeSeconds),
                           end: TimeInterval($0.endTimeSeconds))
        }
    }
}
