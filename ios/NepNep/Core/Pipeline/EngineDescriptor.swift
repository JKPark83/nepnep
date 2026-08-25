import Foundation

/// engines.yml 한 줄 — 전사를 맡길 곳 하나.
///
/// 기기 안 전사와 원격 서버를 같은 타입으로 다뤄서, 어느 쪽을 쓰든 파이프라인은
/// 달라지지 않게 한다. 목록은 코드가 아니라 YAML에 있으므로 서버를 하나 더
/// 붙이는 데 Swift를 고칠 일이 없다.
struct EngineDescriptor: Identifiable, Equatable {
    enum Kind: String {
        /// 기기 안 SpeechTranscriber — 주소도 키도 없다
        case onDevice
        /// OpenAI의 `/v1/audio/transcriptions` 규격. 맥미니 서버·OpenAI·Groq가 모두 이쪽이다.
        case openAI
        /// Deepgram `/v1/listen` — 규격이 따로라 어댑터가 필요하다
        case deepgram
    }

    let id: String
    let name: String
    let kind: Kind
    /// onDevice면 nil
    let baseURL: URL?
    let model: String?
    /// BCP-47. 비면 서버가 알아서 판별한다.
    let language: String?
    /// 키체인에서 API 키를 찾을 이름. 비면 인증 없는 서버.
    let apiKeyRef: String?
    /// 서버가 화자분리까지 해 주는가. 참이면 기기 안 화자분리를 건너뛴다.
    let diarizes: Bool
    /// 서버가 `POST /v1/jobs`로 맡기고 나중에 찾아가는 길을 여는가.
    ///
    /// 한 연결로 전사를 끝까지 기다리면 앱이 백그라운드로 내려가는 순간 iOS가
    /// 소켓을 끊어 버린다("-1005"). 맡겨 두고 가끔 물어보는 쪽은 요청 하나가
    /// 몇 초짜리라 그럴 일이 없다. 넵넵 서버만 이 길을 안다.
    let jobs: Bool
    /// 설정 화면에 한 줄로 붙는 설명
    let note: String?

    var engineID: EngineID { EngineID(id) }
    var needsAPIKey: Bool { apiKeyRef?.isEmpty == false }
    var usesJobAPI: Bool { jobs && kind == .openAI }

    /// 기기 안 전사 — YAML을 못 읽어도 이건 언제나 있다
    static let onDevice = EngineDescriptor(
        id: EngineID.speechTranscriber.rawValue,
        name: "기기 안에서 (기본)",
        kind: .onDevice,
        baseURL: nil,
        model: nil,
        language: "ko",
        apiKeyRef: nil,
        diarizes: false,
        jobs: false,
        note: "인터넷 없이 아이폰 안에서 처리합니다.")
}
