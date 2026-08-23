import SwiftUI

/// 상태별 카드 4종 (와이어프레임 1b 확정: 처리 중 / 완료 / 실패 / 녹음됨)
struct MeetingCardView: View {
    let meeting: Meeting
    var onRetry: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(meeting.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusBadge
            }
            metaLine
            switch meeting.status {
            case .processing:
                progressBar
            case .done:
                if let preview = donePreview {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(2)
                }
            case .failed:
                Button("다시 정리하기", action: onRetry)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
            case .pendingTransfer:
                Text("애플워치에서 녹음했어요. 아이폰이 가까워지면 자동으로 넘어와요.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .recording, .recorded:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    // MARK: - 구성 요소

    @ViewBuilder
    private var statusBadge: some View {
        switch meeting.status {
        case .processing:
            badge(text: "처리 중", color: DesignTokens.statusProcessing, dot: true)
        case .done:
            badge(text: "완료", color: DesignTokens.accent)
        case .failed:
            badge(text: "실패", color: DesignTokens.statusFailed)
        case .pendingTransfer:
            badge(text: "전송 대기 중", color: DesignTokens.statusProcessing)
        case .recorded, .recording:
            badge(text: "녹음됨", color: DesignTokens.textSecondary)
        }
    }

    private func badge(text: String, color: Color, dot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dot {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(MeetingDateFormat.relative(meeting.createdAt))
            Text("·").foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
            Text(MeetingDateFormat.duration(meeting.duration))
            Text("·").foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
            Text(meeting.type.displayName)
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.textSecondary)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DesignTokens.textSecondary.opacity(0.12))
                Capsule()
                    .fill(DesignTokens.statusProcessing)
                    .frame(width: geo.size.width * meeting.processingProgress)
            }
        }
        .frame(height: 4)
        .padding(.top, 2)
    }

    /// 한 줄 요약 우선, 없으면 첫 발화 (05-m3 §5)
    private var donePreview: String? {
        if let oneLiner = meeting.summary?.oneLiner, !oneLiner.isEmpty {
            return oneLiner
        }
        return meeting.utterances.min(by: { $0.orderIndex < $1.orderIndex })?.text
    }
}
