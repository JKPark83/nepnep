import Foundation

enum ResultExporter {
    /// 결과 JSON을 Documents에 저장한다. 파일 공유가 켜져 있어 파일 앱에서 꺼낼 수 있다.
    static func export(_ result: SpikeResult) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)

        let stem = (result.file as NSString).deletingPathExtension
        let engineSlug = result.engine
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let name = "result-\(stem)-\(engineSlug).json"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
