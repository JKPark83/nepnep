import Foundation

/// 심사 대비 상수 (09-m6 §3) — 설정 화면에서 사용
enum AppReviewSupport {
    /// 개인정보 처리방침 — server/public/privacy.html (Vercel 정적 호스팅)
    static let privacyPolicyURL = URL(string: "https://nepnep-server.vercel.app/privacy")!
}
