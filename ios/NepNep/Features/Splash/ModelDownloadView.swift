import SwiftUI

/// 최초 실행 시 음성 인식 엔진(전사·화자분리 모델) 다운로드 화면.
/// 완료(.ready)되어야 onComplete로 홈에 진입한다.
/// 스피너 대신 0→100% 채워지는 링/게이지로 진행률을 표현한다.
struct ModelDownloadView: View {
    @State private var manager = ModelAssetManager.shared
    /// FluidAudio는 다운로드 진행률 콜백이 없어 시간 기반 추정치로 채운다 (완료 시 1로 스냅)
    @State private var diarizerProgress: Double = 0
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            progressRing
            Text("음성 인식 엔진을 준비하고 있어요")
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.top, 24)
            Text("처음 한 번만 내려받아요 · Wi-Fi 연결을 권장해요")
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.top, 4)

            stageCard
                .padding(.horizontal, DesignTokens.margin)
                .padding(.top, 28)

            if case .failed = manager.initialSetupState {
                failureArea
                    .padding(.horizontal, DesignTokens.margin)
                    .padding(.top, 20)
            } else {
                Text("다른 앱으로 이동해도 다운로드는 계속 진행돼요")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.top, 20)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.background)
        .task { await manager.runInitialSetup() }
        .task(id: isDiarizerStage) {
            guard isDiarizerStage else { return }
            // 추정 진행률 — 95%까지 점점 느려지며 차오른다
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                diarizerProgress = min(0.95, diarizerProgress + (0.97 - diarizerProgress) * 0.05)
            }
        }
        .onChange(of: manager.initialSetupState) { _, state in
            guard state == .ready else { return }
            diarizerProgress = 1
            Task {
                // 100% 채워지는 애니메이션을 보여준 뒤 홈 진입
                try? await Task.sleep(for: .milliseconds(500))
                onComplete()
            }
        }
    }

    // MARK: - 진행률

    private var isDiarizerStage: Bool {
        manager.initialSetupState == .downloadingDiarizer
    }

    private var isFailed: Bool {
        if case .failed = manager.initialSetupState { return true }
        return false
    }

    /// 전체 진행률 — 받아쓰기 70% + 화자 구분 30% 가중치
    private var overallProgress: Double {
        if manager.initialSetupState == .ready { return 1 }
        return min(1, manager.speechDownloadProgress * 0.7 + diarizerProgress * 0.3)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(DesignTokens.accent.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: overallProgress)
                .stroke(DesignTokens.accent,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(overallProgress * 100))%")
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(width: 128, height: 128)
        .animation(.easeInOut(duration: 0.3), value: overallProgress)
    }

    // MARK: - 단계 카드

    private var stageCard: some View {
        VStack(spacing: 0) {
            stageRow(title: "받아쓰기 모델",
                     subtitle: speechSubtitle,
                     status: speechStatus,
                     progress: manager.speechDownloadProgress)
            Divider().padding(.leading, 44)
            stageRow(title: "화자 구분 모델",
                     subtitle: diarizerSubtitle,
                     status: diarizerStatus,
                     progress: diarizerProgress)
        }
        .padding(.vertical, 4)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    private enum StageStatus { case pending, active, done }

    private var speechStatus: StageStatus {
        switch manager.initialSetupState {
        case .idle, .downloadingSpeech: return .active
        case .downloadingDiarizer, .ready: return .done
        case .failed: return manager.speechDownloadProgress >= 1 ? .done : .pending
        }
    }

    private var diarizerStatus: StageStatus {
        switch manager.initialSetupState {
        case .downloadingDiarizer: return .active
        case .ready: return .done
        default: return .pending
        }
    }

    private var speechSubtitle: String {
        switch speechStatus {
        case .done: return "완료"
        case .active: return "내려받는 중 · \(Int(manager.speechDownloadProgress * 100))%"
        case .pending: return isFailed ? "중단됨" : "대기 중"
        }
    }

    private var diarizerSubtitle: String {
        switch diarizerStatus {
        case .done: return "완료"
        case .active: return "내려받는 중 · \(Int(diarizerProgress * 100))%"
        case .pending: return isFailed ? "중단됨" : "대기 중"
        }
    }

    private func stageRow(title: String, subtitle: String,
                          status: StageStatus, progress: Double) -> some View {
        HStack(spacing: 12) {
            Group {
                switch status {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.accent)
                case .active:
                    miniRing(progress)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status == .pending
                                     ? DesignTokens.textSecondary
                                     : DesignTokens.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func miniRing(_ value: Double) -> some View {
        ZStack {
            Circle()
                .stroke(DesignTokens.accent.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(DesignTokens.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .animation(.easeInOut(duration: 0.3), value: value)
    }

    // MARK: - 실패

    private var failureArea: some View {
        VStack(spacing: 12) {
            Text("다운로드에 실패했어요. 네트워크 연결을 확인해 주세요.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.statusFailed)
                .multilineTextAlignment(.center)
            Button {
                Task { await manager.runInitialSetup() }
            } label: {
                Text("다시 시도")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
            }
        }
    }
}
