import SwiftUI

/// 회의 한 건을 워치에서 훑어보는 화면.
/// 전문·화자별 발화·할 일은 아이폰에서 본다 — 워치로는 무엇에 관한 회의였는지만 확인한다.
struct WatchMeetingDetailView: View {
    let row: WatchMeetingRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.metaText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(row.statusText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()

                if row.oneLiner.isEmpty {
                    Text("요약이 아직 없어요. 아이폰에서 확인해 주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.oneLiner)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(row.title)
    }
}
