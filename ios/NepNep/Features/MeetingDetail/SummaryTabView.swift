import SwiftData
import SwiftUI

/// 요약 카드 (와이어프레임 1e 확정본: 한 줄 요약 + 템플릿 칩 + 섹션 + 할 일)
/// 템플릿 칩 탭 → 4종 메뉴 → 온디바이스 재요약(digest 캐시로 reduce만 재실행).
struct SummaryTabView: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("요약")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let summary = meeting.summary {
            summaryCard(summary)
                .redacted(reason: isGenerating ? .placeholder : [])
        } else if isGenerating {
            noticeCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("요약을 만들고 있어요…")
                }
            }
        } else if meeting.summaryUnavailable {
            unavailableCard
        } else if meeting.status == .done {
            // 요약 없이 완료된 기존 회의 → 수동 생성
            noticeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("아직 요약이 없어요")
                    Button("요약 만들기") {
                        regenerate(type: meeting.type)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
                }
            }
        }
    }

    // MARK: - 요약 카드 본체

    private func summaryCard(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("한 줄 요약")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                templateChip
            }
            Text(summary.oneLiner)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(summary.sections.enumerated()), id: \.offset) { index, section in
                Divider()
                sectionView(section, style: index == 0 ? .dot : .check)
            }

            if !summary.todos.isEmpty {
                Divider()
                todoSection(summary)
            }
        }
        .padding(16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    /// 템플릿 칩: 탭 → 템플릿 4종 메뉴 → 재요약 (1e 인터랙션 노트)
    private var templateChip: some View {
        Menu {
            ForEach(MeetingType.allCases, id: \.rawValue) { type in
                Button {
                    regenerate(type: type)
                } label: {
                    if type == meeting.type {
                        Label(type.displayName, systemImage: "checkmark")
                    } else {
                        Text(type.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(meeting.type.displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DesignTokens.accent.opacity(0.12))
            .clipShape(Capsule())
        }
        .disabled(isGenerating)
    }

    private enum BulletStyle { case dot, check }

    private func sectionView(_ section: SummarySection, style: BulletStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 8) {
                    switch style {
                    case .dot:
                        Circle()
                            .fill(DesignTokens.textSecondary.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                    case .check:
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DesignTokens.accent)
                            .padding(.top, 3)
                    }
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func todoSection(_ summary: Summary) -> some View {
        let todos = summary.todos.sorted { $0.orderIndex < $1.orderIndex }
        let doneCount = todos.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("할 일")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
                Text("\(doneCount) / \(todos.count) 완료")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(todos) { todo in
                TodoRowView(todo: todo)
            }
        }
    }

    // MARK: - 요약 없음 상태

    private var unavailableCard: some View {
        noticeCard {
            Text(SummaryService.isAvailable
                 ? "요약을 만들지 못했어요. 아래에서 다시 시도할 수 있어요."
                 : "이 기기에서는 온디바이스 요약을 사용할 수 없어요. Apple Intelligence 지원 기기에서 제공돼요.")
            if SummaryService.isAvailable {
                Button("다시 시도") {
                    regenerate(type: meeting.type)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.accent)
                .padding(.top, 12)
            }
        }
    }

    private func noticeCard(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    // MARK: - 재요약

    private func regenerate(type: MeetingType) {
        guard !isGenerating else { return }
        guard SummaryService.isAvailable else {
            meeting.summaryUnavailable = true
            return
        }
        isGenerating = true
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                try await SummaryService.generate(meeting: meeting,
                                                  type: type,
                                                  context: modelContext)
            } catch {
                meeting.summaryUnavailable = meeting.summary == nil
            }
        }
    }
}
