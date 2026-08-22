import SwiftUI

/// 앱 마크 — 와이어프레임 2a의 파형 마크.
/// 앱 아이콘과 같은 24×24 그리드·막대 5개 규칙으로 그린다.
struct AppMarkView: View {
    /// 마크 정사각형 한 변
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: DesignTokens.markFill,
                                 startPoint: .top, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                WaveGlyph()
                    .stroke(DesignTokens.markGlyph,
                            style: StrokeStyle(lineWidth: glyphSize * 2.2 / 24,
                                               lineCap: .round))
                    .frame(width: glyphSize, height: glyphSize)
            }
            .accessibilityHidden(true)
    }

    /// 마크 안쪽 파형이 차지하는 크기 (30pt 마크에 17pt 파형)
    private var glyphSize: CGFloat { size * 17 / 30 }
}

/// 24×24 좌표계의 파형 막대 5개 — 2a 마크의 SVG path 그대로.
private struct WaveGlyph: Shape {
    /// (x, 시작 y, 길이). 모든 막대가 y=12를 기준으로 세로 가운데 정렬된다.
    private static let bars: [(x: CGFloat, y: CGFloat, length: CGFloat)] = [
        (4, 10, 4), (8.5, 7.5, 9), (13, 4.5, 15), (17.5, 8, 8), (21, 10.5, 3),
    ]

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        var path = Path()
        for bar in Self.bars {
            path.move(to: CGPoint(x: bar.x * unit, y: bar.y * unit))
            path.addLine(to: CGPoint(x: bar.x * unit, y: (bar.y + bar.length) * unit))
        }
        return path
    }
}

/// 앱 이름 영역 — 와이어프레임 2b(타이포 락업)에 2a 마크를 얹은 확정본.
/// 커너 한 줄 + 굵고 좁은 이름 + 액센트 점, 왼쪽에 파형 마크.
struct BrandLockupView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            AppMarkView()
                // 마크 아래를 이름 글자 밑선에 맞춘다 (26pt 텍스트의 디센더만큼 올림)
                .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("MEETING RECORDER")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(1.9)
                    .foregroundStyle(DesignTokens.textSecondary)
                HStack(alignment: .bottom, spacing: 6) {
                    Text("넵넵")
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-1.3)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Circle()
                        .fill(DesignTokens.accent)
                        .frame(width: 6, height: 6)
                        .padding(.bottom, 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("넵넵")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        BrandLockupView()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.margin)
            .padding(.vertical, 12)
        Divider()
        Spacer()
    }
    .background(DesignTokens.background)
}
