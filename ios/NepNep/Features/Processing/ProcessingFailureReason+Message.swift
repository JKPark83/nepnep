import Foundation

/// 실패 원인별 사용자 문구 (03-m2 §5, 와이어프레임 1d 실패 상태)
extension ProcessingFailureReason {
    var userMessage: String {
        switch self {
        case .assetMissing:
            return "음성 인식 모델이 아직 준비되지 않았어요.\nWi-Fi에 연결한 뒤 다시 시도해 주세요."
        case .diskFull:
            return "저장 공간이 부족해서 정리하지 못했어요.\n공간을 확보한 뒤 다시 시도해 주세요."
        case .engineError:
            return "정리 중 문제가 생겼어요.\n녹음은 안전하게 저장돼 있으니 다시 시도해 주세요."
        case .cloudFailed:
            return "클라우드 처리에 실패했어요.\n기기에서 처리할까요? 사용량은 차감되지 않았어요."
        case .quotaExceeded:
            return "이번 달 클라우드 시간을 다 썼어요.\n기기에서 처리할까요?"
        }
    }
}
