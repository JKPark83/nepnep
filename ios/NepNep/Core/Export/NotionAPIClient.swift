import Foundation

struct NotionDatabase: Identifiable, Equatable {
    let id: String
    let title: String
}

enum NotionAPIError: LocalizedError {
    case unauthorized          // 401 → 연결 해제 상태로 전환
    case notFound              // 404 → 페이지 삭제됨, 새로 생성 폴백
    case rateLimited
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Notion 연결이 만료됐어요. 설정에서 다시 연결해 주세요."
        case .notFound: return "Notion 페이지를 찾을 수 없어요."
        case .rateLimited: return "Notion 요청이 너무 잦아요. 잠시 후 다시 시도해 주세요."
        case .server(let code): return "Notion 오류가 발생했어요. (\(code))"
        }
    }
}

/// Notion REST 호출 (06-m4 §3)
/// - 버전 고정: 2022-06-28 (data source 분리 이전 안정 버전)
/// - 요청 간 350ms 대기(~3req/s), 429는 Retry-After 존중 후 1회 재시도
struct NotionAPIClient {
    let token: String
    static let version = "2022-06-28"
    static let requestInterval: UInt64 = 350_000_000   // ns

    // MARK: - 조회

    /// 접근 가능한 DB 목록 (피커용)
    func searchDatabases() async throws -> [NotionDatabase] {
        let body: [String: Any] = [
            "filter": ["property": "object", "value": "database"],
            "page_size": 100,
        ]
        let json = try await request(method: "POST", path: "search", body: body)
        let results = json["results"] as? [[String: Any]] ?? []
        return results.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let titleParts = item["title"] as? [[String: Any]] ?? []
            let title = titleParts
                .compactMap { $0["plain_text"] as? String }
                .joined()
            return NotionDatabase(id: id, title: title.isEmpty ? "제목 없음" : title)
        }
    }

    /// DB 스키마에서 title 타입 프로퍼티 키를 찾는다 ("이름"/"Name" 하드코딩 금지)
    func titlePropertyKey(databaseID: String) async throws -> String {
        let json = try await request(method: "GET", path: "databases/\(databaseID)")
        let properties = json["properties"] as? [String: [String: Any]] ?? [:]
        return properties.first { $0.value["type"] as? String == "title" }?.key ?? "Name"
    }

    /// 자식 블록 ID 전체 (페이지네이션)
    func listChildrenIDs(blockID: String) async throws -> [String] {
        var ids: [String] = []
        var cursor: String?
        repeat {
            var path = "blocks/\(blockID)/children?page_size=100"
            if let cursor { path += "&start_cursor=\(cursor)" }
            let json = try await request(method: "GET", path: path)
            let results = json["results"] as? [[String: Any]] ?? []
            ids.append(contentsOf: results.compactMap { $0["id"] as? String })
            cursor = (json["has_more"] as? Bool == true)
                ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return ids
    }

    // MARK: - 쓰기

    /// 페이지 생성 (children은 첫 100블록까지만 — 나머지는 appendChildren)
    func createPage(databaseID: String,
                    titleKey: String,
                    title: String,
                    children: [[String: Any]]) async throws -> (id: String, url: String) {
        let body: [String: Any] = [
            "parent": ["database_id": databaseID],
            "properties": [
                titleKey: ["title": [["text": ["content": title]]]],
            ],
            "children": children,
        ]
        let json = try await request(method: "POST", path: "pages", body: body)
        guard let id = json["id"] as? String, let url = json["url"] as? String else {
            throw NotionAPIError.server(0)
        }
        return (id, url)
    }

    func appendChildren(blockID: String, children: [[String: Any]]) async throws {
        _ = try await request(method: "PATCH",
                              path: "blocks/\(blockID)/children",
                              body: ["children": children])
    }

    func deleteBlock(id: String) async throws {
        _ = try await request(method: "DELETE", path: "blocks/\(id)")
    }

    /// 페이지 조회 — 404 판별용 (재내보내기 전 존재 확인 겸 url 획득)
    func pageURL(pageID: String) async throws -> String {
        let json = try await request(method: "GET", path: "pages/\(pageID)")
        return json["url"] as? String ?? ""
    }

    /// notionPageURL → 32자리 hex 페이지 ID (06-m4 §3 갱신 경로)
    static func pageID(fromURL url: String) -> String? {
        let slug = url.split(separator: "/").last?.split(separator: "?").first ?? ""
        let candidate = slug.split(separator: "-").last.map(String.init) ?? String(slug)
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard candidate.count == 32,
              candidate.unicodeScalars.allSatisfy({ hex.contains($0) }) else { return nil }
        return candidate
    }

    // MARK: - 공통 요청

    private func request(method: String,
                         path: String,
                         body: [String: Any]? = nil,
                         isRetry: Bool = false) async throws -> [String: Any] {
        var urlRequest = URLRequest(url: URL(string: "https://api.notion.com/v1/\(path)")!)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        // 제한 준수: 다음 요청까지 350ms 간격
        try? await Task.sleep(nanoseconds: Self.requestInterval)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299:
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        case 401:
            throw NotionAPIError.unauthorized
        case 404:
            throw NotionAPIError.notFound
        case 429 where !isRetry:
            let retryAfter = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            return try await request(method: method, path: path, body: body, isRetry: true)
        case 429:
            throw NotionAPIError.rateLimited
        default:
            throw NotionAPIError.server(status)
        }
    }
}
