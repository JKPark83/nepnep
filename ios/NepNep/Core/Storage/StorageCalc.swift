import Foundation

/// 저장 공간 집계 (08-m5 §4, F11) — 순수 함수만 (테스트 대상)
enum StorageCalc {
    /// 디렉터리 재귀 합산 (일반 파일만)
    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    /// "1.8GB" / "0.3GB" / "12MB" / "1.9MB" / "500KB" (와이어프레임 1h 표기)
    /// 1MB 미만도 KB로 드러낸다 — 정수 버림으로 "0MB"라 적으면 게이지와 어긋난다.
    static func byteText(_ bytes: Int64) -> String {
        if bytes >= 100_000_000 { return unitText(Double(bytes) / 1_000_000_000, "GB") }
        if bytes >= 1_000_000 { return unitText(Double(bytes) / 1_000_000, "MB") }
        if bytes > 0 { return "\(max(bytes / 1_000, 1))KB" }
        return "0KB"
    }

    /// 소수 첫째 자리까지, 정수면 소수점 생략 ("2GB" / "1.8GB")
    private static func unitText(_ value: Double, _ unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(rounded))\(unit)"
            : String(format: "%.1f%@", rounded, unit)
    }

    /// 전사·요약 = SwiftData 스토어 파일 크기 (default.store + -wal/-shm)
    static func dataStoreBytes() -> Int64 {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("default.store") }
            .reduce(Int64(0)) { $0 + AudioFileStore.fileSize(at: $1) }
    }
}
