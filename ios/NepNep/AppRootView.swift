import SwiftUI

/// 루트 — 스플래시 → (첫 실행 시 온보딩 → 엔진 다운로드) → 홈(1b) + 상세(1e), 알림 딥링크 (04-m2 §5)
struct AppRootView: View {
    private enum LaunchPhase { case splash, onboarding, modelSetup, home }

    @State private var router = Router.shared
    @State private var phase: LaunchPhase = .splash

    var body: some View {
        switch phase {
        case .home:
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: UUID.self) { meetingID in
                        MeetingDetailView(meetingID: meetingID)
                    }
            }
            .tint(DesignTokens.accent)

        case .modelSetup:
            ModelDownloadView {
                withAnimation(.easeOut(duration: 0.25)) { phase = .home }
            }

        case .onboarding:
            OnboardingView {
                withAnimation(.easeOut(duration: 0.25)) { phase = afterOnboarding }
            }

        case .splash:
            SplashView()
                .task {
                    await AppBootstrap.load()
                    let hasOnboarded = UserDefaults.standard
                        .bool(forKey: OnboardingView.hasOnboardedKey)
                    withAnimation(.easeOut(duration: 0.25)) {
                        phase = hasOnboarded ? afterOnboarding : .onboarding
                    }
                }
        }
    }

    /// 온보딩 뒤 목적지 — 모델 미설치면 다운로드, 설치돼 있으면 워밍업만 하고 홈
    private var afterOnboarding: LaunchPhase {
        if ModelAssetManager.isInitialSetupDone {
            ModelAssetManager.shared.prewarmInBackground()
            return .home
        }
        return .modelSetup
    }
}
