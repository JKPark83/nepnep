import SwiftUI

/// 루트 — 스플래시 → (첫 실행 시 온보딩 → 엔진 다운로드) → 홈(1b) + 상세(1e), 알림 딥링크 (04-m2 §5)
struct AppRootView: View {
    private enum LaunchPhase { case splash, onboarding, modelSetup, home }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var router = Router.shared
    @State private var phase: LaunchPhase = .splash

    var body: some View {
        switch phase {
        case .home:
            home
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

    // MARK: - 홈

    /// 아이패드는 목록·상세 2단, 아이폰은 기존 푸시 스택.
    /// `NavigationSplitView`의 compact 자동 접힘에 맡기지 않고 명시적으로 가르는 이유는,
    /// 아이폰 쪽 동작을 지금 코드 그대로 두어 회귀 위험을 없애기 위해서다.
    @ViewBuilder
    private var home: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                HomeView(showsSelection: true)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
            } detail: {
                // Router.path가 두 모드의 단일 상태다 — 알림 딥링크(openMeeting)가
                // path를 [id]로 갈아끼우면 상세 칼럼도 그대로 따라온다.
                if let meetingID = router.path.last {
                    MeetingDetailView(meetingID: meetingID)
                } else {
                    noSelectionPlaceholder
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: UUID.self) { meetingID in
                        MeetingDetailView(meetingID: meetingID)
                    }
            }
        }
    }

    /// 상세 칼럼에 아무것도 선택되지 않았을 때 (아이패드 첫 진입)
    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.document")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
            Text("회의를 골라 주세요")
                .font(.headline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.background)
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
