import Foundation
import UIKit

/// 전사·화자분리 모델 에셋 상태 관리 (03-m2 §5)
@MainActor
@Observable
final class ModelAssetManager {
    static let shared = ModelAssetManager()

    enum AssetState: Equatable {
        case notInstalled
        case downloading(Double)   // 0…1
        case installed
    }

    private static let initialSetupDoneKey = "initialModelSetupDone"

    var speechAssetState: AssetState = .notInstalled

    // MARK: - 최초 설치 다운로드 (온보딩 화면)

    enum InitialSetupState: Equatable {
        case idle
        case downloadingSpeech     // 진행률은 speechDownloadProgress
        case downloadingDiarizer   // FluidAudio는 진행률 미제공 → 스피너
        case failed(String)
        case ready
    }

    private(set) var initialSetupState: InitialSetupState = .idle
    private(set) var speechDownloadProgress: Double = 0

    /// 최초 설치 다운로드를 이미 마쳤는지 (완료 후엔 다운로드 화면 생략)
    static var isInitialSetupDone: Bool {
        UserDefaults.standard.bool(forKey: initialSetupDoneKey)
    }

    /// 최초 실행 시 전사·화자분리 모델 전체 다운로드.
    /// 앱을 전환해도 이어지도록 백그라운드 태스크로 감싼다.
    func runInitialSetup() async {
        guard initialSetupState != .downloadingSpeech,
              initialSetupState != .downloadingDiarizer else { return }

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ModelInitialSetup") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }

        speechDownloadProgress = 0
        initialSetupState = .downloadingSpeech
        do {
            try await SpeechTranscriberEngine.ensureAssetsInstalled { progress in
                Task { @MainActor in self.speechDownloadProgress = progress }
            }
            speechDownloadProgress = 1
            speechAssetState = .installed

            initialSetupState = .downloadingDiarizer
            try await DiarizationService.downloadModels()

            UserDefaults.standard.set(true, forKey: Self.initialSetupDoneKey)
            initialSetupState = .ready
        } catch {
            initialSetupState = .failed(error.localizedDescription)
        }
    }

    // MARK: - 백그라운드 프리웜 (설치 완료 후 재실행 경로)

    /// 백그라운드 프리웜 진행 중 여부 — 홈 상단 준비 배너 노출 조건
    private(set) var isPreparingAssets = false
    private var didStartPrewarm = false

    /// 앱 시작 직후 호출 — 전사·화자분리 모델을 백그라운드로 미리 다운로드한다.
    /// 실패해도 조용히 넘어간다 (전사 시점에 다시 시도되므로).
    func prewarmInBackground() {
        guard !didStartPrewarm else { return }
        didStartPrewarm = true
        Task {
            isPreparingAssets = true
            defer { isPreparingAssets = false }
            try? await ensureSpeechAsset()
            await DiarizationService.prewarm()
        }
    }

    /// SpeechTranscriber 언어 에셋 확보 (AssetInventory, M0 §3)
    func ensureSpeechAsset() async throws {
        try await SpeechTranscriberEngine.ensureAssetsInstalled { progress in
            Task { @MainActor in self.speechAssetState = .downloading(progress) }
        }
        speechAssetState = .installed
    }
}
