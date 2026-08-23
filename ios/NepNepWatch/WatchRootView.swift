import SwiftUI

/// 워치 첫 화면 (이슈 #15 §3) — 녹음 버튼, 전송 대기, 최근 회의 목록.
struct WatchRootView: View {
    @State private var client = WatchSessionClient.shared
    @State private var recorder = WatchRecorder.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    recordButton
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                if !client.pending.isEmpty {
                    Section("전송 대기") {
                        ForEach(client.pending, id: \.meetingID) { envelope in
                            pendingRow(envelope)
                        }
                    }
                }

                Section("최근 회의") {
                    if client.context.rows.isEmpty {
                        Text("아직 회의가 없어요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(client.context.rows) { row in
                            NavigationLink(value: row) {
                                meetingRow(row)
                            }
                        }
                    }
                }
            }
            .navigationTitle("넵넵")
            .navigationDestination(for: WatchMeetingRow.self) { WatchMeetingDetailView(row: $0) }
            .navigationDestination(isPresented: isRecording) { WatchRecordingView() }
        }
        .task { client.refreshPending() }
        .alert("알림",
               isPresented: Binding(get: { recorder.errorMessage != nil },
                                    set: { if !$0 { recorder.errorMessage = nil } })) {
            Button("확인", role: .cancel) { recorder.errorMessage = nil }
        } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    /// 녹음이 시작되면 녹음 화면으로 밀어 넣고, 끝나면 알아서 돌아온다
    private var isRecording: Binding<Bool> {
        Binding(get: { recorder.state == .recording || recorder.state == .pausedByInterruption },
                set: { if !$0 { recorder.stop() } })
    }

    private var recordButton: some View {
        Button {
            Task { await recorder.start() }
        } label: {
            Label("새 녹음", systemImage: "mic.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(recorder.state != .idle)
    }

    private func pendingRow(_ envelope: WatchRecordingEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WatchFormat.time(envelope.startedAt))
                .font(.headline)
            Text("\(WatchFormat.duration(envelope.duration)) · 아이폰 기다리는 중")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func meetingRow(_ row: WatchMeetingRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.headline)
                .lineLimit(2)
            Text(row.metaText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(row.statusText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
