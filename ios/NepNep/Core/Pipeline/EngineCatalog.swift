import Foundation
import Yams

/// engines.yml을 읽어 고를 수 있는 전사 엔진 목록으로 만든다.
///
/// 문서 폴더(파일 앱에서 보이는 곳)에 engines.yml이 있으면 그쪽이 이기고,
/// 없거나 읽다 실패하면 앱 번들에 구워 둔 기본값으로 돌아간다. 사용자가 YAML을
/// 잘못 써서 앱이 전사를 아예 못 하게 되는 상황을 만들지 않기 위해서다.
@MainActor
@Observable
final class EngineCatalog {
    static let shared = EngineCatalog()

    /// 고른 엔진 id. 목록에서 사라진 id가 저장돼 있으면 기기 안 전사로 돌아간다.
    static let selectionKey = "transcription.engineID"

    private(set) var engines: [EngineDescriptor] = []
    /// 문서 폴더 파일을 읽다 실패한 이유. 설정 화면에 그대로 보여준다.
    private(set) var loadError: String?
    /// 번들 기본값이 아니라 문서 폴더 파일을 쓰고 있는지
    private(set) var isUsingOverride = false

    /// 파일 앱에서 편집할 수 있는 자리
    static var overrideURL: URL {
        URL.documentsDirectory.appendingPathComponent("engines.yml")
    }

    private init() { reload() }

    var selected: EngineDescriptor {
        let id = UserDefaults.standard.string(forKey: Self.selectionKey)
        return engines.first { $0.id == id } ?? engines.first ?? .onDevice
    }

    func select(_ descriptor: EngineDescriptor) {
        UserDefaults.standard.set(descriptor.id, forKey: Self.selectionKey)
    }

    /// 고른 엔진을 만들어 준다. 전사를 시작하는 곳은 전부 이걸 거쳐야 한다 —
    /// 엔진을 직접 만들면 설정을 무시하게 된다(실험실이 실제로 그랬다).
    ///
    /// 기기 밖 엔진이 준비돼 있지 않으면 — 서버가 꺼져 있거나 키가 없으면 —
    /// 기기 안 전사로 돌아가고, 무엇으로 돌았는지는 `usedFallback`으로 알린다.
    func makeEngine() async -> (engine: any TranscriptionEngine, usedFallback: Bool) {
        let descriptor = selected
        guard descriptor.kind != .onDevice else { return (SpeechTranscriberEngine(), false) }

        let remote = RemoteTranscriptionEngine(descriptor: descriptor)
        guard await remote.isReady() else { return (SpeechTranscriberEngine(), true) }
        return (remote, false)
    }

    func reload() {
        loadError = nil
        isUsingOverride = false

        if let text = try? String(contentsOf: Self.overrideURL, encoding: .utf8) {
            do {
                engines = try Self.parse(text)
                isUsingOverride = true
                return
            } catch {
                // 덮어쓰기가 깨졌으면 이유를 남기고 번들 기본값으로 계속 간다
                loadError = "문서 폴더의 engines.yml을 읽지 못해 기본 목록을 씁니다: "
                    + error.localizedDescription
            }
        }

        guard let url = Bundle.main.url(forResource: "engines", withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? Self.parse(text), !parsed.isEmpty else {
            engines = [.onDevice]
            return
        }
        engines = parsed
    }

    /// 문서 폴더에 번들 기본값을 복사해 둔다 — 편집을 시작할 자리를 만들어 주는 용도.
    func seedOverrideFile() throws {
        guard let url = Bundle.main.url(forResource: "engines", withExtension: "yml") else { return }
        let text = try String(contentsOf: url, encoding: .utf8)
        try text.write(to: Self.overrideURL, atomically: true, encoding: .utf8)
        reload()
    }

    // MARK: - 파싱

    enum ParseError: LocalizedError {
        case notAMapping
        case missingEngines
        case badEntry(index: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .notAMapping: return "최상위가 키:값 형태가 아닙니다"
            case .missingEngines: return "engines: 목록이 없습니다"
            case .badEntry(let i, let reason): return "\(i + 1)번째 항목 — \(reason)"
            }
        }
    }

    /// 텍스트 → 목록. 상태를 건드리지 않으므로 메인 액터 밖에서도 부른다.
    nonisolated static func parse(_ text: String) throws -> [EngineDescriptor] {
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw ParseError.notAMapping
        }
        guard let rows = root["engines"] as? [[String: Any]] else {
            throw ParseError.missingEngines
        }

        return try rows.enumerated().map { index, row in
            guard let id = (row["id"] as? String)?.trimmed, !id.isEmpty else {
                throw ParseError.badEntry(index: index, reason: "id가 없습니다")
            }
            guard let kindRaw = row["kind"] as? String,
                  let kind = EngineDescriptor.Kind(rawValue: kindRaw) else {
                throw ParseError.badEntry(
                    index: index,
                    reason: "kind는 onDevice / openAI / deepgram 중 하나여야 합니다")
            }

            var baseURL: URL?
            if kind != .onDevice {
                guard let raw = (row["url"] as? String)?.trimmed,
                      let url = URL(string: raw), url.scheme != nil, url.host != nil else {
                    throw ParseError.badEntry(index: index, reason: "url이 없거나 주소 형태가 아닙니다")
                }
                baseURL = url
            }

            return EngineDescriptor(
                id: id,
                name: (row["name"] as? String)?.trimmed ?? id,
                kind: kind,
                baseURL: baseURL,
                model: (row["model"] as? String)?.trimmed,
                language: (row["language"] as? String)?.trimmed,
                apiKeyRef: (row["apiKeyRef"] as? String)?.trimmed,
                diarizes: row["diarizes"] as? Bool ?? false,
                note: (row["note"] as? String)?.trimmed)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
