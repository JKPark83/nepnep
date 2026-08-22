import Foundation
import SwiftData

/// 내보내기 대상 (08-m5 §3) — 시트 선택·마지막 사용 기억에 쓴다
enum ExportTarget: String {
    case notion, google
}

/// Notion·Google Docs 내보내기 실행 (06-m4 §3, 08-m5 §3, F7-2·3·4·5)
/// 시트가 닫혀도 진행되도록 싱글턴이 Task를 보유한다 (와이어프레임 1g 노트 2)
@MainActor
@Observable
final class ExportService {
    static let shared = ExportService()

    static let autoExportKey = "autoExportEnabled"
    static let lastDatabaseIDKey = "notionLastDatabaseID"
    static let lastDatabaseNameKey = "notionLastDatabaseName"
    static let lastFolderIDKey = "googleLastFolderID"
    static let lastFolderNameKey = "googleLastFolderName"
    static let lastTargetKey = "exportLastTarget"

    enum Phase: Equatable {
        case idle
        case running(done: Int, total: Int)
        case done(pageURL: String, updated: Bool)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// 현재(또는 마지막) 실행 대상 — 시트가 진행·완료 문구에 사용
    private(set) var runningTarget: ExportTarget = .notion
    private var exportTask: Task<Void, Never>?

    var lastDatabaseID: String? {
        UserDefaults.standard.string(forKey: Self.lastDatabaseIDKey)
    }
    var lastDatabaseName: String? {
        UserDefaults.standard.string(forKey: Self.lastDatabaseNameKey)
    }
    var lastFolderID: String? {
        UserDefaults.standard.string(forKey: Self.lastFolderIDKey)
    }
    var lastFolderName: String? {
        UserDefaults.standard.string(forKey: Self.lastFolderNameKey)
    }
    var lastTarget: ExportTarget? {
        UserDefaults.standard.string(forKey: Self.lastTargetKey).flatMap(ExportTarget.init(rawValue:))
    }

    func rememberDatabase(_ database: NotionDatabase) {
        UserDefaults.standard.set(database.id, forKey: Self.lastDatabaseIDKey)
        UserDefaults.standard.set(database.title, forKey: Self.lastDatabaseNameKey)
    }

    func rememberFolder(id: String, name: String) {
        UserDefaults.standard.set(id, forKey: Self.lastFolderIDKey)
        UserDefaults.standard.set(name, forKey: Self.lastFolderNameKey)
    }

    func rememberTarget(_ target: ExportTarget) {
        UserDefaults.standard.set(target.rawValue, forKey: Self.lastTargetKey)
    }

    // MARK: - 실행

    func export(meeting: Meeting, databaseID: String) {
        guard exportTask == nil else { return }
        guard let token = NotionAuthService.shared.token else {
            phase = .failed(NotionAPIError.unauthorized.localizedDescription)
            return
        }
        runningTarget = .notion
        rememberTarget(.notion)
        phase = .running(done: 0, total: 1)
        let client = NotionAPIClient(token: token)
        exportTask = Task {
            do {
                let result = try await run(meeting: meeting,
                                           databaseID: databaseID,
                                           client: client)
                meeting.notionPageURL = result.pageURL
                try? meeting.modelContext?.save()
                phase = .done(pageURL: result.pageURL, updated: result.updated)
            } catch is CancellationError {
                phase = .idle
            } catch NotionAPIError.unauthorized {
                NotionAuthService.shared.disconnect()
                phase = .failed(NotionAPIError.unauthorized.localizedDescription)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            exportTask = nil
        }
    }

    func exportGoogle(meeting: Meeting, folderID: String) {
        guard exportTask == nil else { return }
        runningTarget = .google
        rememberTarget(.google)
        phase = .running(done: 0, total: 1)
        exportTask = Task {
            do {
                let result = try await runGoogle(meeting: meeting, folderID: folderID)
                meeting.googleDocURL = result.docURL
                try? meeting.modelContext?.save()
                phase = .done(pageURL: result.docURL, updated: result.updated)
            } catch is CancellationError {
                phase = .idle
            } catch GoogleAPIError.unauthorized, GoogleAuthService.AuthError.unauthorized {
                phase = .failed(GoogleAPIError.unauthorized.localizedDescription)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            exportTask = nil
        }
    }

    func cancel() {
        exportTask?.cancel()
        exportTask = nil
        phase = .idle
    }

    /// 시트를 다시 열 때 완료·실패 상태 초기화
    func reset() {
        guard exportTask == nil else { return }
        phase = .idle
    }

    // MARK: - 내부 흐름

    private func run(meeting: Meeting,
                     databaseID: String,
                     client: NotionAPIClient) async throws -> (pageURL: String, updated: Bool) {
        let blocks = Self.buildBlocks(meeting: meeting)
        let batches = NotionBlockBuilder.chunked(blocks)
        let total = blocks.count

        // 재내보내기: 기존 페이지 갱신 시도, 404면 새로 생성 (06-m4 §3)
        if let url = meeting.notionPageURL,
           let pageID = NotionAPIClient.pageID(fromURL: url) {
            do {
                let pageURL = try await client.pageURL(pageID: pageID)
                let childIDs = try await client.listChildrenIDs(blockID: pageID)
                for id in childIDs {
                    try Task.checkCancellation()
                    try await client.deleteBlock(id: id)
                }
                var done = 0
                for batch in batches {
                    try Task.checkCancellation()
                    try await client.appendChildren(blockID: pageID, children: batch)
                    done += batch.count
                    phase = .running(done: done, total: total)
                }
                return (pageURL, true)
            } catch NotionAPIError.notFound {
                // 사용자가 페이지를 지움 → 새로 생성으로 폴백
            }
        }

        let titleKey = try await client.titlePropertyKey(databaseID: databaseID)
        let first = batches.first ?? []
        let page = try await client.createPage(databaseID: databaseID,
                                               titleKey: titleKey,
                                               title: meeting.title,
                                               children: first)
        var done = first.count
        phase = .running(done: done, total: total)
        for batch in batches.dropFirst() {
            try Task.checkCancellation()
            try await client.appendChildren(blockID: page.id, children: batch)
            done += batch.count
            phase = .running(done: done, total: total)
        }
        return (page.url, false)
    }

    // MARK: - Google 내부 흐름 (08-m5 §2·3)

    private func runGoogle(meeting: Meeting,
                           folderID: String) async throws -> (docURL: String, updated: Bool) {
        let token = try await GoogleAuthService.shared.validAccessToken()
        let client = GoogleDocsClient(token: token)
        let paragraphs = Self.buildGoogleParagraphs(meeting: meeting)

        // 재내보내기: 기존 문서 전체 교체, 404/403(삭제·권한 상실)이면 새로 생성 폴백
        if let url = meeting.googleDocURL,
           let documentID = GoogleDocsClient.documentID(fromURL: url) {
            do {
                let endIndex = try await client.documentEndIndex(documentID: documentID)
                try Task.checkCancellation()
                try await client.batchUpdate(
                    documentID: documentID,
                    requests: GoogleDocsRequestBuilder.replaceRequests(
                        endIndex: endIndex, paragraphs: paragraphs))
                return (url, true)
            } catch GoogleAPIError.notFound {
                // 새로 생성으로 폴백
            }
        }

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ko_KR")
        dateFmt.dateFormat = "M/d"
        let documentID = try await client.createDocument(
            title: "\(meeting.title) — \(dateFmt.string(from: meeting.createdAt))")
        phase = .running(done: 0, total: 1)
        try Task.checkCancellation()
        try await client.batchUpdate(
            documentID: documentID,
            requests: GoogleDocsRequestBuilder.insertRequests(paragraphs: paragraphs))
        try? await client.moveToFolder(fileID: documentID, folderID: folderID)
        return (GoogleDocsClient.docURL(documentID: documentID), false)
    }

    // MARK: - 자동 내보내기 (F7-5 — 연결된 모든 대상에 순차 실행, 실패는 대상별 독립)

    func autoExportAll(meeting: Meeting) {
        Task {
            if NotionAuthService.shared.isConnected,
               let databaseID = lastDatabaseID,
               let token = NotionAuthService.shared.token {
                let client = NotionAPIClient(token: token)
                if let result = try? await run(meeting: meeting,
                                               databaseID: databaseID,
                                               client: client) {
                    meeting.notionPageURL = result.pageURL
                    try? meeting.modelContext?.save()
                }
            }
            if GoogleAuthService.shared.isConnected, let folderID = lastFolderID {
                if let result = try? await runGoogle(meeting: meeting, folderID: folderID) {
                    meeting.googleDocURL = result.docURL
                    try? meeting.modelContext?.save()
                }
            }
            phase = .idle
        }
    }

    // MARK: - Meeting → 블록 입력 변환

    static func buildBlocks(meeting: Meeting) -> [[String: Any]] {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ko_KR")
        dateFmt.dateFormat = "yyyy년 M월 d일 a h:mm"
        let minutes = Int(meeting.duration) / 60
        let meta = "\(dateFmt.string(from: meeting.createdAt)) · \(minutes)분 · 참석 \(meeting.speakers.count)명"

        let nameByID = Dictionary(uniqueKeysWithValues:
            meeting.speakers.map { ($0.id, $0.displayName) })
        let transcript = meeting.utterances
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { u in
                NotionBlockBuilder.TranscriptLine(
                    speakerName: nameByID[u.speakerID] ?? "화자",
                    timeText: Self.timeText(u.startTime),
                    text: u.text)
            }
        let todos = (meeting.summary?.todos ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { NotionBlockBuilder.TodoLine(
                text: $0.text, isDone: $0.isDone,
                assignee: $0.assignee, due: $0.due) }

        return NotionBlockBuilder.blocks(
            title: meeting.title,
            metaText: meta,
            oneLiner: meeting.summary?.oneLiner ?? "",
            sections: meeting.summary?.sections ?? [],
            todos: todos,
            transcript: transcript)
    }

    static func buildGoogleParagraphs(meeting: Meeting) -> [GoogleDocsRequestBuilder.Paragraph] {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ko_KR")
        dateFmt.dateFormat = "yyyy년 M월 d일 a h:mm"
        let minutes = Int(meeting.duration) / 60
        let meta = "\(dateFmt.string(from: meeting.createdAt)) · \(minutes)분 · 참석 \(meeting.speakers.count)명"

        let nameByID = Dictionary(uniqueKeysWithValues:
            meeting.speakers.map { ($0.id, $0.displayName) })
        let transcript = meeting.utterances
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { u in
                GoogleDocsRequestBuilder.TranscriptLine(
                    speakerName: nameByID[u.speakerID] ?? "화자",
                    timeText: Self.timeText(u.startTime),
                    text: u.text)
            }
        let todos = (meeting.summary?.todos ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { GoogleDocsRequestBuilder.TodoLine(
                text: $0.text, isDone: $0.isDone,
                assignee: $0.assignee, due: $0.due) }

        return GoogleDocsRequestBuilder.paragraphs(
            title: meeting.title,
            metaText: meta,
            oneLiner: meeting.summary?.oneLiner ?? "",
            sections: meeting.summary?.sections ?? [],
            todos: todos,
            transcript: transcript)
    }

    private static func timeText(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
