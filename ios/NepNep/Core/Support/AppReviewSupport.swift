import Foundation

/// 심사 대비 상수 (09-m6 §3) — 페이월·설정에서 공용
enum AppReviewSupport {
    /// 개인정보 처리방침 — server/public/privacy.html (Vercel 정적 호스팅)
    static let privacyPolicyURL = URL(string: "https://nepnep-server.vercel.app/privacy")!
    /// 이용약관 — server/public/terms.html
    static let termsURL = URL(string: "https://nepnep-server.vercel.app/terms")!
    /// Apple 표준 EULA (계정 없는 구독 심사 포인트)
    static let eulaURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
