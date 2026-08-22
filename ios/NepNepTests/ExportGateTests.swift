import XCTest
@testable import NepNep

final class ExportGateTests: XCTestCase {

    // 대상을 아직 안 고르면 어떤 연결 상태에서도 비활성
    func testNoTargetIsNeverExportable() {
        XCTAssertFalse(ExportGate.canExport(
            target: nil, notionConnected: true, googleConnected: true, databaseID: "db"))
    }

    // Notion: 연결 + 데이터베이스가 둘 다 있어야 활성
    func testNotionRequiresConnectionAndDatabase() {
        XCTAssertTrue(ExportGate.canExport(
            target: .notion, notionConnected: true, googleConnected: false, databaseID: "db"))
        XCTAssertFalse(ExportGate.canExport(
            target: .notion, notionConnected: true, googleConnected: false, databaseID: nil))
        XCTAssertFalse(ExportGate.canExport(
            target: .notion, notionConnected: false, googleConnected: false, databaseID: "db"))
    }

    // Google: 폴더 미선택(내 드라이브 최상위)도 정상이라 연결만 보면 된다 (#5)
    func testGoogleIsExportableWithoutFolder() {
        XCTAssertTrue(ExportGate.canExport(
            target: .google, notionConnected: false, googleConnected: true, databaseID: nil))
    }

    // Google: 연결이 없으면 비활성
    func testGoogleRequiresConnection() {
        XCTAssertFalse(ExportGate.canExport(
            target: .google, notionConnected: true, googleConnected: false, databaseID: "db"))
    }

    // Notion 대상일 때 Google 연결은 판단에 끼어들지 않는다 (그 반대도)
    func testTargetsAreJudgedIndependently() {
        XCTAssertFalse(ExportGate.canExport(
            target: .notion, notionConnected: false, googleConnected: true, databaseID: "db"))
        XCTAssertTrue(ExportGate.canExport(
            target: .google, notionConnected: false, googleConnected: true, databaseID: nil))
    }
}
