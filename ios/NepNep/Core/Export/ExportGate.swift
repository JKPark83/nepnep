import Foundation

/// 내보내기 버튼 활성 조건 (와이어프레임 1g 대상 선택)
/// Notion은 페이지를 만들 데이터베이스가 반드시 필요하지만,
/// Google Docs는 폴더 미선택이 곧 "내 드라이브 최상위"라 연결 여부만 본다.
enum ExportGate {
    static func canExport(target: ExportTarget?,
                          notionConnected: Bool,
                          googleConnected: Bool,
                          databaseID: String?) -> Bool {
        switch target {
        case .notion: return notionConnected && databaseID != nil
        case .google: return googleConnected
        case nil: return false
        }
    }
}
