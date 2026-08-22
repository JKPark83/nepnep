import SwiftUI
import UniformTypeIdentifiers

struct SpikeView: View {
    @State private var runner = SpikeRunner()
    @State private var engine: SpikeEngine = .apple
    @State private var pickedURL: URL?
    @State private var showImporter = false
    @State private var exportMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("입력") {
                    Button {
                        showImporter = true
                    } label: {
                        Label(pickedURL?.lastPathComponent ?? "오디오 파일 선택 (16kHz mono WAV)",
                              systemImage: "waveform")
                    }
                    Picker("엔진", selection: $engine) {
                        ForEach(SpikeEngine.allCases) { e in
                            Text(e.rawValue).tag(e)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("실행") {
                    Button {
                        guard let url = pickedURL else { return }
                        Task { await runner.run(url: url, engine: engine) }
                    } label: {
                        if runner.isRunning {
                            HStack {
                                ProgressView()
                                Text(runner.statusLine)
                            }
                        } else {
                            Text("실행")
                        }
                    }
                    .disabled(pickedURL == nil || runner.isRunning)

                    LabeledContent("상태", value: runner.statusLine)
                    if let err = runner.lastError {
                        Text(err)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                }

                if let result = runner.lastResult {
                    Section("결과") {
                        LabeledContent("전사", value: String(format: "%.1f초", result.transcribeSec))
                        LabeledContent("화자분리", value: String(format: "%.1f초", result.diarizeSec))
                        LabeledContent("발열", value: "\(result.thermalAfterTranscribe) → \(result.thermalAfterDiarize)")
                        LabeledContent("배터리", value: String(
                            format: "%.0f%% → %.0f%%",
                            result.batteryStart * 100, result.batteryEnd * 100))
                        LabeledContent("화자 수", value: "\(Set(result.segments.map(\.speaker)).count)")
                        Text(result.text.prefix(300) + (result.text.count > 300 ? "…" : ""))
                            .font(.caption)

                        Button("JSON 내보내기 (파일 앱)") {
                            do {
                                let url = try ResultExporter.export(result)
                                exportMessage = "저장됨: \(url.lastPathComponent)"
                            } catch {
                                exportMessage = "저장 실패: \(error.localizedDescription)"
                            }
                        }
                        if let exportMessage {
                            Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("넵넵 스파이크")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result {
                    pickedURL = url
                    runner.lastResult = nil
                    exportMessage = nil
                }
            }
        }
    }
}
