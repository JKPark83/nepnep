import AVFoundation
import SwiftUI
import UserNotifications

/// 온보딩 (09-m6 §1, 와이어프레임 1a) — 가치 제안 3장 → 권한 요청.
/// 첫 실행 1회만 노출. 모델 다운로드는 이어지는 ModelDownloadView가 담당한다.
struct OnboardingView: View {
    static let hasOnboardedKey = "hasOnboarded"

    private enum Step { case slides, permission }

    @State private var step: Step = .slides
    @State private var slideIndex = 0
    @State private var isRequesting = false
    var onComplete: () -> Void

    private struct Slide {
        let icon: String
        let title: String
        let subtitle: String
    }

    /// 1a 확정본 카피 그대로 (PRD §7 1a)
    private let slides: [Slide] = [
        Slide(icon: "infinity",
              title: "회의 녹음, 무료로 무제한",
              subtitle: "시간 제한도 횟수 제한도 없습니다.\n필요한 만큼 녹음하고 정리하세요."),
        Slide(icon: "iphone.badge.location.slash",
              title: "녹음은 기기 안에서만 처리돼요",
              subtitle: "전사·화자 구분·요약이 모두 아이폰에서 실행됩니다.\n오디오는 서버로 보내지 않습니다."),
        Slide(icon: "sparkles.rectangle.stack",
              title: "끝나면 알아서 정리해 둘게요",
              subtitle: "완성된 회의록이 Notion 또는 Google Docs로\n바로 저장됩니다."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .slides: slidesStep
            case .permission: permissionStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.background)
    }

    // MARK: - 가치 제안 3장 (1a 노트 1·2)

    private var slidesStep: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("건너뛰기") {
                    withAnimation(.easeOut(duration: 0.25)) { step = .permission }
                }
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.horizontal, DesignTokens.margin)
                .padding(.top, 12)
            }

            TabView(selection: $slideIndex) {
                ForEach(slides.indices, id: \.self) { i in
                    slidePage(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 인디케이터 — 현재 위치만 accent (1a 노트 2)
            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { i in
                    Circle()
                        .fill(i == slideIndex
                              ? DesignTokens.accent
                              : DesignTokens.textSecondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 24)

            Button {
                if slideIndex < slides.count - 1 {
                    withAnimation { slideIndex += 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { step = .permission }
                }
            } label: {
                Text(slideIndex < slides.count - 1 ? "다음" : "시작하기")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, DesignTokens.margin)
            .padding(.bottom, 20)
        }
    }

    private func slidePage(_ slide: Slide) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: slide.icon)
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.accent)
            Text(slide.title)
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
            Text(slide.subtitle)
                .font(.callout)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 권한 요청 (1a 노트 3)

    private var permissionStep: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("두 가지 권한이 필요해요")
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
            Text("언제든 설정에서 다시 바꿀 수 있습니다.")
                .font(.callout)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.top, 6)

            VStack(spacing: 0) {
                permissionRow(icon: "mic.fill", title: "마이크", badge: "필수",
                              detail: "회의 음성을 녹음합니다.")
                Divider().padding(.leading, 56)
                permissionRow(icon: "bell.badge", title: "알림", badge: "선택",
                              detail: "정리가 끝나면 알려드립니다.")
            }
            .padding(.vertical, 4)
            .background(DesignTokens.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
            .padding(.horizontal, DesignTokens.margin)
            .padding(.top, 32)

            Spacer()

            Button {
                requestPermissions()
            } label: {
                Text("권한 허용")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isRequesting)
            .padding(.horizontal, DesignTokens.margin)
            .padding(.bottom, 20)
        }
    }

    private func permissionRow(icon: String, title: String,
                               badge: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.textSecondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 마이크 → 알림 순서로 시스템 시트. 거부해도 진행한다 (09-m6 §1).
    private func requestPermissions() {
        isRequesting = true
        Task {
            _ = await AVAudioApplication.requestRecordPermission()
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(true, forKey: Self.hasOnboardedKey)
            onComplete()
        }
    }
}
