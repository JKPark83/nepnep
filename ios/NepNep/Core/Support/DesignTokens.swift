import SwiftUI
import UIKit

/// 00-overview §4 디자인 토큰. 와이어프레임 1a~1i의 단일 기준.
/// 화면 코드에서 색·간격을 하드코딩하지 말 것.
enum DesignTokens {
    // MARK: 색 (라이트/다크)

    static let accent = Color(light: 0x0F7A72, dark: 0x3FBFB0)
    static let background = Color(light: 0xF7F6F3, dark: 0x0B0B0C)
    static let card = Color(light: 0xFFFFFF, dark: 0x18191B)
    static let textPrimary = Color(light: 0x17181A, dark: 0xF2F2F5)
    static let textSecondary = Color(light: 0x6B6B70, dark: 0xA8A8AD)
    static let statusProcessing = Color(light: 0xB4741C, dark: 0xE0A34A)
    static let statusFailed = Color(light: 0xB03A31, dark: 0xFF8579)

    /// 화자 아바타 팔레트 — Speaker.colorIndex 0..7 순환 (와이어프레임 1e·1f)
    static let speakerColors: [Color] = [
        Color(light: 0x0F7A72, dark: 0x0F7A72),
        Color(light: 0x4A6FA5, dark: 0x4A6FA5),
        Color(light: 0xA5734A, dark: 0xA5734A),
        Color(light: 0x6B5FA5, dark: 0x6B5FA5),
        Color(light: 0xA54A6F, dark: 0xA54A6F),
        Color(light: 0x4AA573, dark: 0x4AA573),
        Color(light: 0x5F8CA5, dark: 0x5F8CA5),
        Color(light: 0xA5964A, dark: 0xA5964A),
    ]

    // MARK: 레이아웃 (8pt 그리드)

    static let margin: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let buttonHeight: CGFloat = 52
    static let fabSize: CGFloat = 68

    /// 넓은 화면에서 콘텐츠를 묶어 두는 최대 폭.
    /// 아이패드 전폭(최대 1366pt)으로 늘어나면 버튼 하나가 화면을 가로지르고
    /// 본문 한 줄이 너무 길어져 읽기 어렵다.
    static let contentMaxWidth: CGFloat = 600
}

extension View {
    /// regular 폭(아이패드, 넓은 Stage Manager 창)에서만 콘텐츠를 가운데로 모은다.
    /// compact(아이폰, 좁은 창)에서는 아무것도 하지 않으므로 기존 레이아웃 그대로다.
    func contentWidthLimited(_ limit: CGFloat = DesignTokens.contentMaxWidth) -> some View {
        modifier(ContentWidthLimit(limit: limit))
    }
}

private struct ContentWidthLimit: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let limit: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            // 안쪽 frame이 폭을 묶고, 바깥 frame이 남은 자리에서 가운데로 민다
            content
                .frame(maxWidth: limit)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        })
    }
}
