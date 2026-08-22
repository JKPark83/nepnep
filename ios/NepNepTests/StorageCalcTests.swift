import XCTest
@testable import NepNep

final class StorageCalcTests: XCTestCase {

    // 임시 디렉터리(중첩 포함) 재귀 합산
    func testDirectorySizeRecursive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageCalcTests-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(count: 1_000).write(to: root.appendingPathComponent("a.m4a"))
        try Data(count: 2_500).write(to: sub.appendingPathComponent("b.m4a"))

        XCTAssertEqual(StorageCalc.directorySize(root), 3_500)
        XCTAssertEqual(StorageCalc.directorySize(root.appendingPathComponent("없는폴더")), 0)
    }

    // 와이어프레임 1h 표기: "1.8GB" / "2GB" / "0.3GB" / "12MB"
    func testByteTextFormatting() {
        XCTAssertEqual(StorageCalc.byteText(1_800_000_000), "1.8GB")
        XCTAssertEqual(StorageCalc.byteText(2_000_000_000), "2GB")
        XCTAssertEqual(StorageCalc.byteText(300_000_000), "0.3GB")
        XCTAssertEqual(StorageCalc.byteText(12_000_000), "12MB")
        XCTAssertEqual(StorageCalc.byteText(0), "0MB")
    }
}
