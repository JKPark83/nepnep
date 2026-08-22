import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google OAuth 연결 (08-m5 §1, F7-1)
/// iOS 클라이언트 ID + PKCE 직교환 — secret이 없어 서버 라우트 불필요 (Notion과 다른 점).
/// scope는 documents + drive.file(앱이 만든 파일만 접근) 최소화.
@MainActor
@Observable
final class GoogleAuthService: NSObject {
    static let shared = GoogleAuthService()

    /// Google Cloud Console의 iOS OAuth 클라이언트 ID (예: "1234-abc.apps.googleusercontent.com")
    static let clientID = "GOOGLE_CLIENT_ID_MISSING"
    /// iOS 클라이언트의 리다이렉트는 클라이언트 ID를 뒤집은 커스텀 스킴
    static var callbackScheme: String {
        clientID.components(separatedBy: ".").reversed().joined(separator: ".")
    }
    static var redirectURI: String { "\(callbackScheme):/oauth2redirect" }
    private static let scope =
        "https://www.googleapis.com/auth/documents https://www.googleapis.com/auth/drive.file"

    private static let accessTokenKey = "googleAccessToken"
    private static let refreshTokenKey = "googleRefreshToken"
    private static let expiryKey = "googleAccessTokenExpiry"

    private(set) var isConnected: Bool =
        KeychainStore.string(for: GoogleAuthService.refreshTokenKey) != nil

    enum AuthError: LocalizedError {
        case cancelled
        case exchangeFailed
        case notConfigured
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .cancelled: return "연결을 취소했어요."
            case .exchangeFailed: return "Google 연결에 실패했어요. 잠시 후 다시 시도해 주세요."
            case .notConfigured: return "Google 연동 설정이 아직 준비되지 않았어요."
            case .unauthorized: return "Google 연결이 만료됐어요. 다시 연결해 주세요."
            }
        }
    }

    // MARK: - 연결

    func connect() async throws {
        guard Self.clientID != "GOOGLE_CLIENT_ID_MISSING" else { throw AuthError.notConfigured }

        let verifier = Self.randomURLSafeString()
        let challenge = Self.codeChallenge(verifier: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: Self.callbackScheme) { url, error in
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
        let token = try await Self.requestToken(form: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ])
        guard let refresh = token.refreshToken else { throw AuthError.exchangeFailed }
        KeychainStore.setString(refresh, for: Self.refreshTokenKey)
        storeAccess(token)
        isConnected = true
    }

    /// 유효한 access token 반환 — 만료(3600s) 시 refresh token으로 자동 갱신.
    /// 갱신 실패(revoked)면 연결 해제 상태로 전환한다 (08-m5 §1).
    func validAccessToken() async throws -> String {
        if let token = KeychainStore.string(for: Self.accessTokenKey),
           UserDefaults.standard.double(forKey: Self.expiryKey) > Date.now.timeIntervalSince1970 + 60 {
            return token
        }
        guard let refresh = KeychainStore.string(for: Self.refreshTokenKey) else {
            throw AuthError.unauthorized
        }
        do {
            let token = try await Self.requestToken(form: [
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": Self.clientID,
            ])
            storeAccess(token)
            return token.accessToken
        } catch AuthError.unauthorized {
            disconnect()
            throw AuthError.unauthorized
        }
    }

    func disconnect() {
        KeychainStore.delete(Self.accessTokenKey)
        KeychainStore.delete(Self.refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.expiryKey)
        UserDefaults.standard.removeObject(forKey: ExportService.lastFolderIDKey)
        UserDefaults.standard.removeObject(forKey: ExportService.lastFolderNameKey)
        isConnected = false
    }

    // MARK: - 토큰 요청

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private static func requestToken(form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw AuthError.exchangeFailed
        }
        switch status {
        case 200:
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        case 400, 401:
            // invalid_grant 등 — refresh token 폐기됨
            throw AuthError.unauthorized
        default:
            throw AuthError.exchangeFailed
        }
    }

    private func storeAccess(_ token: TokenResponse) {
        KeychainStore.setString(token.accessToken, for: Self.accessTokenKey)
        UserDefaults.standard.set(
            Date.now.timeIntervalSince1970 + token.expiresIn, forKey: Self.expiryKey)
    }

    // MARK: - PKCE

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
