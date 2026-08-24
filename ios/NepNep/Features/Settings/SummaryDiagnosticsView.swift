import SwiftUI

/// 설정 > 요약 진단 (#21)
/// 마지막 요약 실행 몇 건의 단계별 로그를 그대로 보여준다.
/// 긴 회의에서 요약이 실패했을 때 어디서 무엇 때문에 멈췄는지 기기에서 바로 확인하고,
/// 길게 눌러 복사해 이슈에 붙일 수 있게 하는 것이 목적이다.
struct SummaryDiagnosticsView: View {
    @State private var records = SummaryDiagnostics.records

    var body: some View {
        List {
            if records.isEmpty {
                Text("아직 요약을 실행한 기록이 없어요.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(records) { record in
                Section {
                    ForEach(Array(record.events.enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.caption.monospaced())
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                } header: {
                    header(record)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.background)
        // 진행 중인 실행을 열어 두고 지켜볼 수 있어야 한다 — 멈춘 지점이 여기서 보인다
        .task {
            while !Task.isCancelled {
                records = SummaryDiagnostics.records
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .navigationTitle("요약 진단")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("비우기") {
                    SummaryDiagnostics.clear()
                    records = []
                }
                .tint(DesignTokens.accent)
                .disabled(records.isEmpty)
            }
        }
    }

    private func header(_ record: SummaryRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.meetingTitle)
                    .lineLimit(1)
                Spacer()
                Text(record.inProgress ? "진행 중"
                     : (record.succeeded ? "성공" : "실패"))
                    .foregroundStyle(record.inProgress ? DesignTokens.textSecondary
                                     : (record.succeeded ? DesignTokens.accent : .red))
            }
            Text("\(record.startedAt.formatted(date: .abbreviated, time: .standard)) · "
                 + String(format: "%.1f초", record.duration))
            if !record.succeeded, !record.inProgress {
                Text(record.outcome).foregroundStyle(.red)
            }
        }
        .font(.caption)
        .textCase(nil)
        // 길게 눌러 이 실행의 로그 전체를 복사 — 이슈에 붙이기 위한 최소 수단
        .contextMenu {
            Button("로그 복사") {
                UIPasteboard.general.string = SummaryRunLog.plainText(record)
            }
        }
    }
}
