import SwiftUI

/// 처리 진행 화면 (와이어프레임 1d 확정본)
/// 홈 카드 탭·녹음 종료 직후 양쪽에서 진입한다.
struct ProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var meeting: Meeting

    private enum Stage: Int, CaseIterable {
        case transcribe, diarize, summarize

        var title: String {
            switch self {
            case .transcribe: return "받아쓰기"
            case .diarize: return "화자 구분"
            case .summarize: return "요약"
            }
        }
    }

    /// 진행률 배분(ProcessingCoordinator)과 동일 기준으로 현재 단계 판정
    private var activeStage: Stage? {
        guard meeting.status == .processing else { return nil }
        if meeting.processingProgress < 0.55 { return .transcribe }
        if meeting.processingProgress < 0.8 { return .diarize }
        return .summarize
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            header
            stageCard
                .padding(.horizontal, DesignTokens.margin)
                .padding(.top, 28)
            if meeting.status == .processing {
                Text("화면을 닫아도 백그라운드에서 계속 정리돼요")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.top, 16)
            }
            Spacer()
            bottomButtons
                .padding(.horizontal, DesignTokens.margin)
                .padding(.bottom, 24)
        }
        .contentWidthLimited()
        .frame(maxWidth: .infinity)
        .background(DesignTokens.background)
    }

    // MARK: - 헤더

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            switch meeting.status {
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(DesignTokens.statusFailed)
                Text("정리하지 못했어요")
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(failureMessage)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(DesignTokens.accent)
                Text("정리가 끝났어요")
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.textPrimary)
            default:
                Text("회의록을 정리하고 있어요")
                    .font(.title3.bold())
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            Text(meeting.title)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, DesignTokens.margin)
    }

    private var failureReason: ProcessingFailureReason {
        meeting.failureReasonRaw
            .flatMap(ProcessingFailureReason.init(rawValue:)) ?? .engineError
    }

    private var failureMessage: String { failureReason.userMessage }

    // MARK: - 단계 카드 (1d: 완료 단계는 체크로 접힘, 스피너는 하나만)

    private var stageCard: some View {
        VStack(spacing: 0) {
            ForEach(Stage.allCases, id: \.rawValue) { stage in
                stageRow(stage)
                if stage != .summarize {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    private func stageRow(_ stage: Stage) -> some View {
        HStack(spacing: 14) {
            stageIcon(stage)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.title)
                    .font(.subheadline.weight(stage == activeStage ? .semibold : .regular))
                    .foregroundStyle(stageDone(stage) || stage == activeStage
                                     ? DesignTokens.textPrimary
                                     : DesignTokens.textSecondary)
                if stage == activeStage, let label = meeting.processingStage {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                if stage == .summarize, meeting.status == .done, meeting.summaryUnavailable {
                    // 실패 사유가 있으면 그대로 — 없으면 기기 미지원 (#21)
                    Text(meeting.summaryFailureReason ?? "이 기기에서는 요약을 만들 수 없었어요")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
            if stage == activeStage, let percent = stagePercent(stage) {
                Text("\(percent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(14)
    }

    /// 단계 내 진행률(%) — 전사 0~0.55, 요약 0.8~1 구간을 각각 0~100으로 환산
    private func stagePercent(_ stage: Stage) -> Int? {
        switch stage {
        case .transcribe:
            return Int(meeting.processingProgress / 0.55 * 100)
        case .summarize:
            return Int((meeting.processingProgress - 0.8) / 0.2 * 100)
        case .diarize:
            return nil
        }
    }

    private func stageDone(_ stage: Stage) -> Bool {
        switch stage {
        case .transcribe:
            return meeting.status == .done || meeting.processingProgress >= 0.55
        case .diarize:
            return meeting.status == .done || meeting.processingProgress >= 0.8
        case .summarize:
            return meeting.status == .done && !meeting.summaryUnavailable
        }
    }

    @ViewBuilder
    private func stageIcon(_ stage: Stage) -> some View {
        if stageDone(stage) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.accent)
        } else if stage == activeStage {
            ProgressView()
        } else {
            Image(systemName: "circle")
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.4))
        }
    }

    // MARK: - 하단 버튼

    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 12) {
            if meeting.status == .failed {
                Button {
                    ProcessingCoordinator.shared.enqueue(meeting: meeting)
                } label: {
                    Text("다시 시도")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                        .background(DesignTokens.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            if meeting.status == .done {
                Button {
                    dismiss()
                    Router.shared.openMeeting(meeting.id)
                } label: {
                    Text("전사본 보기")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                        .background(DesignTokens.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            Button {
                dismiss()
            } label: {
                Text("홈으로")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(DesignTokens.card)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
