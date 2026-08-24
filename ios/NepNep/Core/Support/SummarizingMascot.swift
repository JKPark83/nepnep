import SwiftUI

/// 요약이 도는 동안 보여주는 마스코트 (#21).
/// 긴 회의는 요약에 몇 분이 걸리는데 자리표시자만 깔려 있으면 멈춘 화면과 구분되지 않는다.
/// 계속 움직이는 그림 하나로 "살아 있다"를 보이고, 종이에 채워지는 줄로 진행률을 같이 읽힌다.
///
/// 캐릭터는 이미지 에셋 없이 도형으로만 그린다 — 다크 모드와 임의 크기를 함께 감당하기 위해서다.
struct SummarizingMascot: View {
    /// 0~1 진행률. 종이에 채워지는 줄 수로 표현한다.
    var progress: Double

    /// 기준 크기 — 이 값을 바꾸면 전체가 비례해서 커진다
    private let unit: CGFloat = 108

    var body: some View {
        KeyframeAnimator(initialValue: Pose(), repeating: true) { pose in
            ZStack(alignment: .bottomLeading) {
                paper
                    .rotationEffect(.degrees(-7))
                    .offset(x: unit * 0.42, y: -unit * 0.06)
                character(pose)
                    .offset(y: pose.bob)
            }
            // 종이 오른쪽 끝이 0.94unit이라 폭을 여기에 맞춰야 그림이 가운데로 온다
            .frame(width: unit * 0.96, height: unit * 0.92, alignment: .bottomLeading)
        } keyframes: { _ in
            // 몸통 위아래 — 숨 쉬는 느낌만 나게 4pt
            KeyframeTrack(\.bob) {
                CubicKeyframe(-4, duration: 0.6)
                CubicKeyframe(0, duration: 0.6)
                CubicKeyframe(-4, duration: 0.6)
                CubicKeyframe(0, duration: 0.6)
            }
            // 연필 — 짧게 왔다 갔다 하며 계속 끄적인다. 한 주기(2.4초)를 다 채워야
            // 애니메이션이 반복될 때 손이 멈춰 보이지 않는다.
            KeyframeTrack(\.pencil) {
                CubicKeyframe(10, duration: 0.3)
                CubicKeyframe(-12, duration: 0.3)
                CubicKeyframe(10, duration: 0.3)
                CubicKeyframe(-12, duration: 0.3)
                CubicKeyframe(10, duration: 0.3)
                CubicKeyframe(-12, duration: 0.3)
                CubicKeyframe(10, duration: 0.3)
                CubicKeyframe(-12, duration: 0.3)
            }
            // 눈 깜빡임 — 주기당 한 번, 아주 짧게
            KeyframeTrack(\.eye) {
                LinearKeyframe(1, duration: 1.9)
                LinearKeyframe(0.08, duration: 0.09)
                LinearKeyframe(1, duration: 0.09)
                LinearKeyframe(1, duration: 0.32)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - 종이

    private var paper: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: unit * 0.05)
                .fill(DesignTokens.card)
                .overlay {
                    RoundedRectangle(cornerRadius: unit * 0.05)
                        .strokeBorder(DesignTokens.textSecondary.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: unit * 0.055) {
                ForEach(0..<5, id: \.self) { line in
                    Capsule()
                        .fill(DesignTokens.accent.opacity(filled(line) ? 0.75 : 0.14))
                        .frame(width: unit * lineWidth(line), height: unit * 0.032)
                        .animation(.easeOut(duration: 0.35), value: filled(line))
                }
            }
            .padding(unit * 0.075)
        }
        .frame(width: unit * 0.52, height: unit * 0.66)
    }

    /// 진행률을 다섯 줄로 나눠 채운다 — 첫 줄은 시작하자마자 켜서 정지 화면처럼 보이지 않게 한다
    private func filled(_ line: Int) -> Bool {
        progress >= Double(line) / 5
    }

    private func lineWidth(_ line: Int) -> CGFloat {
        [0.34, 0.28, 0.32, 0.22, 0.3][line]
    }

    // MARK: - 캐릭터

    private func character(_ pose: Pose) -> some View {
        ZStack {
            // 연필 든 팔 — 어깨를 축으로 돌려야 손이 종이 위에서 움직인다
            arm
                .rotationEffect(.degrees(pose.pencil), anchor: .init(x: 0.1, y: 0.5))
                .offset(x: unit * 0.28, y: -unit * 0.02)

            body(pose)
        }
        .frame(width: unit * 0.62, height: unit * 0.66)
    }

    private func body(_ pose: Pose) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.2, style: .continuous)
                .fill(
                    LinearGradient(colors: DesignTokens.markFill,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: unit * 0.5, height: unit * 0.46)
                .shadow(color: DesignTokens.accent.opacity(0.25), radius: 8, y: 4)

            // 머리 위 더듬이 — 회의를 '듣는' 안테나
            antenna
                .offset(y: -unit * 0.3)

            face(pose)
        }
    }

    private var antenna: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(DesignTokens.accent)
                .frame(width: unit * 0.07, height: unit * 0.07)
            Capsule()
                .fill(DesignTokens.accent.opacity(0.7))
                .frame(width: unit * 0.018, height: unit * 0.09)
        }
    }

    private func face(_ pose: Pose) -> some View {
        VStack(spacing: unit * 0.035) {
            HStack(spacing: unit * 0.115) {
                eye(pose)
                eye(pose)
            }
            // 입 — 아래로 볼록한 반원
            Circle()
                .trim(from: 0.05, to: 0.45)
                .stroke(DesignTokens.markGlyph.opacity(0.85),
                        style: .init(lineWidth: unit * 0.018, lineCap: .round))
                .frame(width: unit * 0.09, height: unit * 0.09)
        }
        .offset(y: -unit * 0.01)
    }

    private func eye(_ pose: Pose) -> some View {
        Capsule()
            .fill(DesignTokens.markGlyph)
            .frame(width: unit * 0.05, height: unit * 0.07)
            .scaleEffect(y: pose.eye, anchor: .center)
    }

    /// 팔 + 연필. 연필은 몸 색과 대비되도록 따로 칠한다.
    private var arm: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(DesignTokens.markFill[1])
                .frame(width: unit * 0.16, height: unit * 0.055)
            ZStack(alignment: .trailing) {
                Capsule()
                    .fill(Color(red: 0.95, green: 0.72, blue: 0.28))
                    .frame(width: unit * 0.2, height: unit * 0.045)
                // 연필심
                Triangle()
                    .fill(DesignTokens.textPrimary.opacity(0.8))
                    .frame(width: unit * 0.05, height: unit * 0.045)
            }
        }
    }

    /// 애니메이션 한 주기 동안 움직이는 값들
    private struct Pose {
        var bob: CGFloat = 0
        var pencil: Double = 10
        var eye: CGFloat = 1
    }
}

/// 연필심용 오른쪽 방향 삼각형
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 마스코트 + 진행률 막대 + 단계 문구를 묶은 카드 본문 (#21)
struct SummarizingIndicator: View {
    var progress: Double
    /// 쉬는 중처럼 진행률만으로는 알 수 없는 상태 한 줄 (#21)
    var notice: String?

    /// 실제 진행률 위에 시간 기반 추정치를 얹은 표시값.
    ///
    /// 마지막 10%(reduce)는 모델 호출 딱 한 번이라 값이 0.9에 1분 넘게 붙어 있는다.
    /// 구간 요지 캐시를 쓰는 재요약은 시작하자마자 0.9로 뛰므로 화면 전체가 멈춘 것처럼 보였다.
    /// ModelDownloadView가 화자 구분 단계에서 쓰는 방식과 같이, 다음 지점을 향해 천천히 채운다.
    @State private var displayed: Double = 0

    var body: some View {
        VStack(spacing: 14) {
            SummarizingMascot(progress: displayed)

            VStack(spacing: 6) {
                Text(stageText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .contentTransition(.opacity)
                // 진행률이 0일 때도 막대가 보이게 최소 폭을 준다
                ProgressView(value: max(displayed, 0.02))
                    .tint(DesignTokens.accent)
                    .animation(.easeOut(duration: 0.4), value: displayed)
                Text("\(Int(displayed * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
                if let notice {
                    // 진행률이 멈춰 있어도 여기서 이유를 읽을 수 있어야 한다
                    Label(notice, systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            // 실제 진행률이 갱신되지 않는 동안에도 막대가 조금씩 나아간다.
            // 다음 지점에 점근하기만 하고 넘지 않아, 실제 진행을 앞질러 100%가 되지 않는다.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                displayed = max(displayed, progress)
                let target = Self.creepTarget(for: progress)
                if displayed < target {
                    displayed += (target - displayed) * 0.045
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("요약하는 중")
        .accessibilityValue("\(Int(displayed * 100))퍼센트")
    }

    /// 추정치가 향해 갈 지점 — 실제 진행률보다 딱 한 걸음(9%p) 앞까지만 간다.
    /// 다 끝났으면(1) 추정 없이 100%로 채운다.
    static func creepTarget(for progress: Double) -> Double {
        progress >= 1 ? 1 : min(progress + 0.09, 0.99)
    }

    /// 진행률 0.9까지가 구간별 요약(map), 그 뒤가 최종 정리(reduce)다.
    /// 마지막 10%가 통째로 한 번의 모델 호출이라 오래 걸리므로 문구를 따로 둔다.
    private var stageText: String {
        progress < 0.9 ? "회의를 나눠 읽고 있어요" : "읽은 내용을 하나로 정리하고 있어요"
    }
}
