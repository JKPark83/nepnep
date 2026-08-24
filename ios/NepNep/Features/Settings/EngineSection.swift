import SwiftUI

/// 설정 > 전사 엔진 (#21 후속)
///
/// 목록은 engines.yml에서 온다 — 파일 앱에 engines.yml을 넣어 두면 재빌드 없이
/// 서버를 늘리거나 바꿀 수 있다. API 키는 YAML이 아니라 여기서 받아 키체인에 넣는다.
struct EngineSection: View {
    @State private var catalog = EngineCatalog.shared
    @AppStorage(EngineCatalog.selectionKey) private var selectedID = EngineID.speechTranscriber.rawValue

    @State private var apiKey = ""
    @State private var probeResult: ProbeResult?
    @State private var isProbing = false
    @State private var seedError: String?

    private enum ProbeResult {
        case ok
        case failed(String)
    }

    private var selected: EngineDescriptor {
        catalog.engines.first { $0.id == selectedID } ?? catalog.engines.first ?? .onDevice
    }

    var body: some View {
        Section {
            Picker("전사 엔진", selection: $selectedID) {
                ForEach(catalog.engines) { engine in
                    Text(engine.name).tag(engine.id)
                }
            }
            .tint(DesignTokens.accent)
            .onChange(of: selectedID) { _, _ in
                probeResult = nil
                loadKeyForSelection()
            }

            if let note = selected.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            if let ref = selected.apiKeyRef, !ref.isEmpty {
                SecureField("API 키", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { saveKey(ref: ref) }

                Button {
                    saveKey(ref: ref)
                } label: {
                    Text(apiKey.isEmpty ? "저장된 키 지우기" : "키 저장")
                        .foregroundStyle(DesignTokens.accent)
                }
            }

            if selected.kind != .onDevice {
                Button {
                    probe()
                } label: {
                    HStack {
                        Text("연결 확인")
                            .foregroundStyle(DesignTokens.accent)
                        Spacer()
                        switch probeResult {
                        case .ok:
                            Text("연결됨")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        case .failed:
                            Text("실패")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        case nil:
                            if isProbing { ProgressView() }
                        }
                    }
                }
                .disabled(isProbing)
            }

            if case .failed(let message) = probeResult {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let loadError = catalog.loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                seed()
            } label: {
                Text(catalog.isUsingOverride ? "설정 파일 다시 읽기" : "파일 앱에서 목록 편집하기")
                    .foregroundStyle(DesignTokens.accent)
            }

            if let seedError {
                Text(seedError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("전사 엔진")
        } footer: {
            Text(footerText)
        }
        .onAppear { loadKeyForSelection() }
    }

    private var footerText: String {
        let base = "녹음을 글로 옮길 곳을 고릅니다. 기기 밖 서버를 고르면 녹음 파일이 그 서버로 올라갑니다."
        return catalog.isUsingOverride
            ? base + " 지금은 파일 앱의 engines.yml을 쓰고 있습니다."
            : base + " 목록을 늘리려면 아래 버튼으로 engines.yml을 만든 뒤 파일 앱 > 나의 iPhone > 넵넵 에서 고치세요."
    }

    // MARK: - 동작

    /// 키를 그대로 다시 보여주지는 않는다 — 저장돼 있으면 가려진 자리표시만 채운다.
    private func loadKeyForSelection() {
        guard let ref = selected.apiKeyRef, !ref.isEmpty else {
            apiKey = ""
            return
        }
        apiKey = EngineKeychain.key(for: ref) ?? ""
    }

    private func saveKey(ref: String) {
        EngineKeychain.setKey(apiKey, for: ref)
        probeResult = nil
    }

    private func probe() {
        isProbing = true
        probeResult = nil
        let descriptor = selected
        Task {
            do {
                try await RemoteTranscriptionEngine(descriptor: descriptor).probe()
                probeResult = .ok
            } catch {
                probeResult = .failed(error.localizedDescription)
            }
            isProbing = false
        }
    }

    private func seed() {
        seedError = nil
        do {
            if catalog.isUsingOverride {
                catalog.reload()
            } else {
                try catalog.seedOverrideFile()
            }
        } catch {
            seedError = "설정 파일을 만들지 못했습니다: \(error.localizedDescription)"
        }
    }
}
