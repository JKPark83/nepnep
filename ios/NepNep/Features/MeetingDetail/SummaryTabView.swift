import SwiftData
import SwiftUI

/// 요약 카드 (와이어프레임 1e: 한 줄 요약 + 섹션 + 할 일)
/// 회의 유형이 일반 하나로 정리되면서 템플릿 칩은 걷어냈다 (#21).
struct SummaryTabView: View {
    @Bindable var meeting: Meeting
    /// 요약을 다시 시작할 때 부모가 이 카드로 스크롤하도록 알린다 (#21)
    var onRegenerateStart: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @State private var isGenerating = false
    /// 요약 진행률 0~1 — 마스코트 카드가 읽는다 (#21)
    @State private var progress: Double = 0
    /// "요청이 몰려 쉬는 중" 같은 상태 한 줄 — 멈춘 것과 기다리는 것을 구분해 준다 (#21)
    @State private var notice: String?

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
        // 요약을 도는 동안에는 기존 카드를 흐리게 덮는 대신 마스코트 카드로 갈아 끼운다.
        // 자리표시자만 깔면 몇 분짜리 대기가 멈춘 화면과 구분되지 않았다 (#21).
        if isGenerating {
            noticeCard {
                SummarizingIndicator(progress: progress, notice: notice)
            }
        } else if let summary = meeting.summary {
            summaryCard(summary)
        } else if meeting.summaryUnavailable {
            unavailableCard
        } else if meeting.status == .done {
            // 요약 없이 완료된 기존 회의 → 수동 생성
            noticeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("아직 요약이 없어요")
                    Button("요약 만들기") {
                        regenerate()
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
            metaRows(summary)

            Divider()
            Text("한 줄 요약")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Text(summary.oneLiner)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if summary.isLegacyShape {
                // 템플릿 개편 전에 만들어진 요약 — 저장된 평문 섹션을 그대로 보여준다.
                // 다시 요약을 누르면 새 회의록 형태로 바뀐다 (#21).
                ForEach(Array(summary.sections.enumerated()), id: \.offset) { _, section in
                    Divider()
                    legacySection(section)
                }
            } else {
                if !summary.briefing.isEmpty {
                    Divider()
                    briefingSection(summary.briefing)
                }
                if !summary.decisions.isEmpty {
                    Divider()
                    decisionSection(summary.decisions)
                }
                if !summary.todos.isEmpty {
                    Divider()
                    actionItemSection(summary)
                }
                if !summary.agenda.isEmpty {
                    Divider()
                    agendaSection(summary.agenda, decisions: summary.decisions)
                }
                if !summary.parkingLot.isEmpty {
                    Divider()
                    parkingLotSection(summary.parkingLot)
                }
            }

            if summary.isLegacyShape, !summary.todos.isEmpty {
                Divider()
                actionItemSection(summary)
            }

            // 유형 칩이 사라지면서 이미 요약된 회의를 다시 돌릴 길이 없어졌다 (#21).
            // 프롬프트를 손본 뒤 예전 회의로 결과를 확인하려면 이 버튼이 필요하다.
            Divider()
            Button {
                regenerate()
            } label: {
                Label("다시 요약", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(DesignTokens.accent)
            .disabled(isGenerating)
        }
        .padding(16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    // MARK: - 머리말

    /// 일시·장소·참석·불참. 장소와 불참은 회의에서 말이 나왔을 때만 채워지므로,
    /// 비어 있으면 "미상"을 적는 대신 줄째로 뺀다 (#21).
    private func metaRows(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("일시", "\(MeetingDateFormat.relative(meeting.createdAt)) · "
                    + MeetingDateFormat.duration(meeting.duration))
            if !summary.place.isEmpty {
                metaRow("장소", summary.place)
            }
            let attendees = meeting.speakers
                .sorted { $0.label < $1.label }
                .map(\.displayName)
                .joined(separator: ", ")
            if !attendees.isEmpty {
                metaRow("참석", attendees)
            }
            if !summary.absentees.isEmpty {
                metaRow("불참", summary.absentees)
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 회의록 섹션

    private func briefingSection(_ lines: [String]) -> some View {
        sectionShell(SummaryTemplates.briefingTitle) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 14, alignment: .trailing)
                    bodyText(line)
                }
            }
        }
    }

    private func decisionSection(_ decisions: [DecisionItem]) -> some View {
        sectionShell(SummaryTemplates.decisionsTitle) {
            ForEach(Array(decisions.enumerated()), id: \.offset) { i, decision in
                rowShell(tag: "D-\(i + 1)") {
                    bodyText(decision.content)
                    detailBadges([("근거", decision.rationale), ("결정자", decision.decider)])
                }
            }
            ForEach(SummaryTemplates.reconditionLines(decisions), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionItemSection(_ summary: Summary) -> some View {
        let todos = summary.todos.sorted { $0.orderIndex < $1.orderIndex }
        let doneCount = todos.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(SummaryTemplates.actionItemsTitle)
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

    private func agendaSection(_ agenda: [AgendaItem],
                               decisions: [DecisionItem]) -> some View {
        sectionShell(SummaryTemplates.agendaTitle) {
            ForEach(Array(agenda.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("안건 \(i + 1). \(item.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.issue.isEmpty {
                        labeledLine("논점", item.issue)
                    }
                    ForEach(Array(item.opinions.enumerated()), id: \.offset) { _, opinion in
                        labeledLine("의견", opinion)
                    }
                    if !item.conclusion.isEmpty {
                        let reference = SummaryTemplates.decisionReference(for: item.conclusion,
                                                                          in: decisions)
                        labeledLine("결론", item.conclusion
                                    + (reference.map { " → \($0)" } ?? ""))
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }

    private func parkingLotSection(_ issues: [OpenIssue]) -> some View {
        sectionShell(SummaryTemplates.parkingLotTitle) {
            ForEach(Array(issues.enumerated()), id: \.offset) { i, issue in
                rowShell(tag: "P-\(i + 1)") {
                    bodyText(issue.item)
                    detailBadges([("사유", issue.reason), ("재논의", issue.revisitAt)])
                }
            }
        }
    }

    // MARK: - 공용 조각

    private func sectionShell(_ title: String,
                              @ViewBuilder _ rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            rows()
        }
    }

    /// "D-1" 같은 행 번호를 왼쪽에 세우고 내용을 오른쪽에 쌓는다
    private func rowShell(tag: String,
                          @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(tag)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(DesignTokens.accent)
                .padding(.top, 2)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) { content() }
            Spacer(minLength: 0)
        }
    }

    /// 값이 있는 것만 배지로 — 없는 칸은 "미정"을 채우지 않고 지운다
    private func detailBadges(_ pairs: [(String, String)]) -> some View {
        let filled = pairs.filter { !$0.1.isEmpty }
        return Group {
            if !filled.isEmpty {
                HStack(spacing: 6) {
                    ForEach(filled, id: \.0) { label, value in
                        Text("\(label) \(value)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DesignTokens.textSecondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func labeledLine(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 26, alignment: .leading)
            bodyText(text)
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(DesignTokens.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 개편 전 요약의 평문 섹션 그리기
    private func legacySection(_ section: SummarySection) -> some View {
        sectionShell(section.title) {
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(DesignTokens.textSecondary.opacity(0.5))
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    bodyText(bullet)
                }
            }
        }
    }

    // MARK: - 요약 없음 상태

    private var unavailableCard: some View {
        noticeCard {
            // 실패 사유를 그대로 보여준다 — 원인이 무엇이든 같은 문구만 나오던 문제 (#21)
            Text(SummaryService.isAvailable
                 ? (meeting.summaryFailureReason ?? "요약을 만들지 못했어요.")
                    + " 아래에서 다시 시도할 수 있어요."
                 : "이 기기에서는 온디바이스 요약을 사용할 수 없어요. Apple Intelligence 지원 기기에서 제공돼요.")
            if SummaryService.isAvailable {
                Button("다시 시도") {
                    regenerate()
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

    private func regenerate() {
        guard !isGenerating else { return }
        guard SummaryService.isAvailable else {
            meeting.summaryUnavailable = true
            return
        }
        progress = 0
        notice = nil
        isGenerating = true
        onRegenerateStart()
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                try await SummaryService.generate(meeting: meeting,
                                                  context: modelContext,
                                                  onProgress: { progress = $0 },
                                                  onNotice: { notice = $0 })
                // 막대가 100%까지 차오르는 걸 보여준 뒤 카드로 넘어간다.
                // 곧장 갈아 끼우면 90%에서 화면이 바뀌어 버려 끝난 건지 알 수 없었다 (#21).
                progress = 1
                try? await Task.sleep(for: .milliseconds(600))
            } catch {
                meeting.summaryUnavailable = meeting.summary == nil
            }
        }
    }
}
