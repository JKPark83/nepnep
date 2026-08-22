import Foundation

enum GoogleAPIError: LocalizedError {
    case unauthorized
    case notFound
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Google 연결이 만료됐어요. 다시 연결해 주세요."
        case .notFound: return "문서를 찾을 수 없어요."
        case .http(let status, let message):
            return message.isEmpty ? "Google 요청에 실패했어요 (\(status))" : message
        }
    }
}

/// Google Docs·Drive REST 클라이언트 (08-m5 §2)
struct GoogleDocsClient {
    let token: String

    private static let docsBase = URL(string: "https://docs.googleapis.com/v1/documents")!
    private static let driveBase = URL(string: "https://www.googleapis.com/drive/v3/files")!

    static func docURL(documentID: String) -> String {
        "https://docs.google.com/document/d/\(documentID)/edit"
    }

    /// "https://docs.google.com/document/d/{id}/edit" → id
    static func documentID(fromURL url: String) -> String? {
        guard let range = url.range(of: "/document/d/") else { return nil }
        let rest = url[range.upperBound...]
        let id = rest.prefix { $0 != "/" && $0 != "?" }
        return id.isEmpty ? nil : String(id)
    }

    // MARK: - Docs

    func createDocument(title: String) async throws -> String {
        struct Response: Decodable { let documentId: String }
        let response: Response = try await request(
            url: Self.docsBase, method: "POST", body: ["title": title])
        return response.documentId
    }

    func batchUpdate(documentID: String, requests: [[String: Any]]) async throws {
        struct Response: Decodable {}
        let _: Response = try await request(
            url: Self.docsBase.appendingPathComponent("\(documentID):batchUpdate"),
            method: "POST",
            body: ["requests": requests])
    }

    /// 본문 마지막 endIndex — 재내보내기의 deleteContentRange 상한 (08-m5 §2)
    func documentEndIndex(documentID: String) async throws -> Int {
        struct Element: Decodable { let endIndex: Int? }
        struct Body: Decodable { let content: [Element] }
        struct Response: Decodable { let body: Body }
        var components = URLComponents(
            url: Self.docsBase.appendingPathComponent(documentID),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: "body.content.endIndex")]
        let response: Response = try await request(url: components.url!, method: "GET")
        return response.body.content.compactMap(\.endIndex).max() ?? 1
    }

    // MARK: - Drive

    func moveToFolder(fileID: String, folderID: String) async throws {
        struct Response: Decodable { let id: String }
        var components = URLComponents(
            url: Self.driveBase.appendingPathComponent(fileID),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "addParents", value: folderID),
            URLQueryItem(name: "fields", value: "id"),
        ]
        let _: Response = try await request(url: components.url!, method: "PATCH")
    }

    struct DriveFolder: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// 폴더 목록 — 이름 검색 지원 (08-m5 §2). drive.file scope라 앱이 만든·사용자가 고른 폴더만 보인다.
    func listFolders(nameQuery: String = "") async throws -> [DriveFolder] {
        struct Response: Decodable { let files: [DriveFolder] }
        var q = "mimeType='application/vnd.google-apps.folder' and trashed=false"
        if !nameQuery.isEmpty {
            let escaped = nameQuery.replacingOccurrences(of: "'", with: "\\'")
            q += " and name contains '\(escaped)'"
        }
        var components = URLComponents(url: Self.driveBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
        ]
        let response: Response = try await request(url: components.url!, method: "GET")
        return response.files
    }

    // MARK: - 공통

    private func request<Response: Decodable>(url: URL,
                                              method: String,
                                              body: [String: Any]? = nil) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw GoogleAPIError.http(0, "")
        }
        switch status {
        case 200...299:
            if data.isEmpty, let empty = "{}".data(using: .utf8) {
                return try JSONDecoder().decode(Response.self, from: empty)
            }
            return try JSONDecoder().decode(Response.self, from: data)
        case 401:
            throw GoogleAPIError.unauthorized
        case 403, 404:
            // 삭제·권한 상실 — 새 문서 생성 폴백 대상 (08-m5 §2)
            throw GoogleAPIError.notFound
        default:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
            throw GoogleAPIError.http(status, message ?? "")
        }
    }

    private struct ErrorBody: Decodable {
        struct Inner: Decodable { let message: String? }
        let error: Inner?
    }
}
