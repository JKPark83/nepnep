import Foundation

/// 라이브 자막 텍스트 누적기 (녹음 중 미리보기)
///
/// `SpeechTranscriber`는 같은 구간을 두 번 준다 — 말하는 도중에는 미확정
/// (volatile) 추정치를 계속 갈아 끼우다가, 구간이 끝나면 확정(isFinal) 결과를
/// 한 번 준다. 미확정 조각을 그냥 이어 붙이면 같은 말이 몇 겹씩 쌓이므로,
/// 확정된 것만 누적하고 미확정 꼬리는 매번 통째로 교체한다.
///
/// 라이브 경로에서 오디오 없이 단위 테스트가 가능한 유일한 조각이라 값 타입으로 뺐다.
struct LiveTranscriptBuffer: Equatable {
    /// 들고 있을 확정 텍스트의 최대 글자 수.
    /// 4시간 녹음이면 수만 자가 쌓이는데 자막은 최근 몇 줄만 보이면 되므로 앞에서 버린다.
    static let maxCharacters = 2000

    private(set) var finalized = ""
    /// 아직 확정되지 않은 꼬리 — 화면에서 흐리게 그린다
    private(set) var pending = ""

    /// 화면에 그릴 전체 문자열
    var display: String { finalized + pending }
    var isEmpty: Bool { finalized.isEmpty && pending.isEmpty }

    /// 확정 결과가 왔다. 이 구간을 추정하던 꼬리는 확정본으로 대체된다.
    mutating func commit(_ text: String, limit: Int = maxCharacters) {
        pending = ""
        finalized += Self.fragment(text, after: finalized)
        if finalized.count > limit {
            finalized = String(finalized.suffix(limit))
        }
    }

    /// 미확정 꼬리 — 누적이 아니라 교체다
    mutating func setPending(_ text: String) {
        pending = Self.fragment(text, after: finalized)
    }

    mutating func reset() {
        finalized = ""
        pending = ""
    }

    /// 이어 붙일 조각. 전사기가 조각마다 앞뒤 공백을 붙여 줄 때도 있고 안 붙일
    /// 때도 있어서, 여기서 한 번 정리하고 필요할 때만 공백을 끼워 넣는다.
    private static func fragment(_ text: String, after base: String) -> String {
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return "" }
        guard !base.isEmpty else { return piece }
        return " " + piece
    }
}
