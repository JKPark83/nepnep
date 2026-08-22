import SwiftUI
import UIKit

/// 요약 공유 메뉴 (#4) — 시스템 공유 시트로 카카오톡·메일·Files 등에 넘긴다.
/// 계정 연동이 필요 없고 네트워크도 타지 않는다.
struct ShareSummaryMenu<Label: View>: View {
    let meeting: Meeting
    @ViewBuilder var label: () -> Label

    @State private var payload: Payload?
    @State private var buildError: String?

    var body: some View {
        Menu {
            ForEach(SummaryShareBuilder.Format.allCases) { format in
                Button {
                    present(format)
                } label: {
                    SwiftUI.Label(format.title, systemImage: format.icon)
                }
            }
        } label: {
            label()
        }
        .disabled(!SummaryShareBuilder.canShare(meeting: meeting))
        .sheet(item: $payload) { payload in
            ActivityView(items: payload.items)
        }
        .alert("공유할 파일을 만들지 못했어요",
               isPresented: .init(get: { buildError != nil },
                                  set: { if !$0 { buildError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(buildError ?? "")
        }
    }

    /// 파일 생성은 누른 뒤에만 한다 — 화면을 그릴 때마다 PDF를 만들지 않도록
    private func present(_ format: SummaryShareBuilder.Format) {
        do {
            payload = Payload(items: try SummaryShareBuilder.items(meeting: meeting,
                                                                   format: format))
        } catch {
            buildError = error.localizedDescription
        }
    }

    private struct Payload: Identifiable {
        let id = UUID()
        let items: [Any]
    }
}

/// UIActivityViewController 래퍼 — 텍스트·파일 URL을 그대로 넘긴다
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
