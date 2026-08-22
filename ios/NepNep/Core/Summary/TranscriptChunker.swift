import Foundation

/// 전사를 Foundation Models 프롬프트 예산(4,096토큰 합산 한도) 안으로 분할 (05-m3 §3)
/// 발화(줄) 중간은 자르지 않고, 한도 초과 단일 발화만 문장 단위로 강제 분할한다.
enum TranscriptChunker {
    /// 청크당 한국어 약 1,200자 — instructions·출력 몫을 뺀 안전 예산
    static let defaultLimit = 1_200

    /// - Parameter lines: "화자: 발화" 형태의 줄 목록 (순서 유지)
    /// - Returns: 각 원소가 개행으로 합쳐진 청크 텍스트
    static func chunk(_ lines: [String], limit: Int = defaultLimit) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var currentCount = 0

        func flush() {
            if !current.isEmpty {
                chunks.append(current.joined(separator: "\n"))
                current = []
                currentCount = 0
            }
        }

        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let pieces = line.count > limit ? split(longLine: line, limit: limit) : [line]
            for piece in pieces {
                // +1: 개행 몫
                if currentCount > 0, currentCount + piece.count + 1 > limit {
                    flush()
                }
                current.append(piece)
                currentCount += piece.count + 1
            }
        }
        flush()
        return chunks
    }

    /// 한도 초과 단일 발화 → 문장 단위 분할, 문장조차 초과하면 글자 단위 강제 분할
    static func split(longLine: String, limit: Int) -> [String] {
        var sentences: [String] = []
        var buffer = ""
        for ch in longLine {
            buffer.append(ch)
            if ".!?…\n。".contains(ch) {
                sentences.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { sentences.append(buffer) }

        var pieces: [String] = []
        var current = ""
        for sentence in sentences {
            if sentence.count > limit {
                // 구두점 없는 초장문 → 글자 단위 강제 분할
                if !current.isEmpty { pieces.append(current); current = "" }
                var rest = Substring(sentence)
                while rest.count > limit {
                    pieces.append(String(rest.prefix(limit)))
                    rest = rest.dropFirst(limit)
                }
                current = String(rest)
                continue
            }
            if !current.isEmpty, current.count + sentence.count > limit {
                pieces.append(current)
                current = ""
            }
            current += sentence
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                     .filter { !$0.isEmpty }
    }
}
