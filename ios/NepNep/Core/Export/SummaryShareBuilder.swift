import Foundation

/// Meeting → 공유 시트에 실을 항목 (#4)
/// 네트워크·계정 연동을 타지 않는다 — 전부 기기 안에서 만든다.
enum SummaryShareBuilder {
    enum Format: String, CaseIterable, Identifiable {
        case text, markdown, pdf
        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "텍스트로 공유"
            case .markdown: return "Markdown 파일로 공유"
            case .pdf: return "PDF로 공유"
            }
        }

        var icon: String {
            switch self {
            case .text: return "text.alignleft"
            case .markdown: return "doc.plaintext"
            case .pdf: return "doc.richtext"
            }
        }
    }

    /// 요약이 있어야 공유할 게 있다
    static func canShare(meeting: Meeting) -> Bool {
        meeting.summary != nil
    }

    static func plainText(meeting: Meeting) -> String {
        let input = Input(meeting: meeting)
        return SummaryTextBuilder.plainText(title: input.title,
                                            metaText: input.metaText,
                                            oneLiner: input.oneLiner,
                                            sections: input.sections,
                                            todos: input.todos)
    }

    /// 공유 시트에 넘길 항목 — 파일 형식은 임시 파일 URL을 만들어 돌려준다
    static func items(meeting: Meeting, format: Format) throws -> [Any] {
        let input = Input(meeting: meeting)
        switch format {
        case .text:
            return [plainText(meeting: meeting)]
        case .markdown:
            let markdown = SummaryTextBuilder.markdown(title: input.title,
                                                       metaText: input.metaText,
                                                       oneLiner: input.oneLiner,
                                                       sections: input.sections,
                                                       todos: input.todos)
            return [try write(Data(markdown.utf8),
                              name: input.fileName, ext: "md")]
        case .pdf:
            let data = SummaryPDFRenderer.pdfData(title: input.title,
                                                  metaText: input.metaText,
                                                  oneLiner: input.oneLiner,
                                                  sections: input.sections,
                                                  todos: input.todos)
            return [try write(data, name: input.fileName, ext: "pdf")]
        }
    }

    /// 공유 시트가 파일명을 그대로 쓰도록 회의 제목으로 임시 파일을 만든다.
    /// 같은 회의를 다시 공유하면 덮어쓴다 — 매번 폴더가 늘지 않게.
    private static func write(_ data: Data, name: String, ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("share", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Meeting → 빌더 입력

    private struct Input {
        let title: String
        let metaText: String
        let oneLiner: String
        let sections: [SummarySection]
        let todos: [SummaryTextBuilder.TodoLine]
        let fileName: String

        init(meeting: Meeting) {
            let dateFmt = DateFormatter()
            dateFmt.locale = Locale(identifier: "ko_KR")
            dateFmt.dateFormat = "yyyy년 M월 d일 a h:mm"
            let minutes = Int(meeting.duration) / 60

            title = meeting.title
            metaText = "\(dateFmt.string(from: meeting.createdAt)) · \(minutes)분 · 참석 \(meeting.speakers.count)명"
            oneLiner = meeting.summary?.oneLiner ?? ""
            sections = meeting.summary?.sections ?? []
            todos = (meeting.summary?.todos ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { SummaryTextBuilder.TodoLine(
                    text: $0.text, isDone: $0.isDone,
                    assignee: $0.assignee, due: $0.due) }
            fileName = SummaryTextBuilder.safeFileName(meeting.title)
        }
    }
}
