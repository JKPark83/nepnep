import AuthenticationServices
import Foundation
import UIKit

/// Notion OAuth 연결 (06-m4 §2, F7-1)
/// ASWebAuthenticationSession → code → 서버 exchange → Keychain 저장.
@MainActor
@Observable
final class NotionAuthService: NSObject {
    static let shared = NotionAuthService()

    static let clientID = "3c4d872b-594c-8160-be0a-0037412bd309"
    static let serverBaseURL = URL(string: "https://nepnep-server.vercel.app")!
    /// Notion은 HTTPS 리다이렉트만 허용 → 서버 콜백이 nepnep:// 스킴으로 되돌려 준다
    static let redirectURI = "https://nepnep-server.vercel.app/v1/oauth/notion/callback"

    private static let tokenKey = "notionAccessToken"
    private static let workspaceKey = "notionWorkspaceName"

    private(set) var workspaceName: String? =
        UserDefaults.standard.string(forKey: NotionAuthService.workspaceKey)

    var token: String? { KeychainStore.string(for: Self.tokenKey) }
    var isConnected: Bool { token != nil }

    enum AuthError: LocalizedError {
        case cancelled
        case exchangeFailed
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .cancelled: return "연결을 취소했어요."
            case .exchangeFailed: return "Notion 연결에 실패했어요. 잠시 후 다시 시도해 주세요."
            case .notConfigured: return "Notion 연동 설정이 아직 준비되지 않았어요."
            }
        }
    }

    func connect() async throws {
        guard Self.clientID != "NOTION_CLIENT_ID_MISSING" else { throw AuthError.notConfigured }

        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "nepnep") { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else if let error, (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error ?? AuthError.exchangeFailed)
                    }
                }
            session.presentationContextProvider = self
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.exchangeFailed
        }
        try await exchange(code: code)
    }

    private func exchange(code: String) async throws {
        var request = URLRequest(
            url: Self.serverBaseURL.appendingPathComponent("v1/oauth/notion/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ["code": code, "redirectUri": Self.redirectURI])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.exchangeFailed
        }
        struct ExchangeResponse: Decodable {
            let accessToken: String
            let workspaceName: String
        }
        let result = try JSONDecoder().decode(ExchangeResponse.self, from: data)
        KeychainStore.setString(result.accessToken, for: Self.tokenKey)
        workspaceName = result.workspaceName
        UserDefaults.standard.set(result.workspaceName, forKey: Self.workspaceKey)
    }

    /// 연결 해제 — 토큰·대상 DB 기억을 모두 지운다 (401 수신 시에도 호출)
    func disconnect() {
        KeychainStore.delete(Self.tokenKey)
        workspaceName = nil
        UserDefaults.standard.removeObject(forKey: Self.workspaceKey)
        UserDefaults.standard.removeObject(forKey: ExportService.lastDatabaseIDKey)
        UserDefaults.standard.removeObject(forKey: ExportService.lastDatabaseNameKey)
    }
}

extension NotionAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
