import SwiftUI

/// 설정 — 연동(M4) 섹션 (와이어프레임 1h)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = NotionAuthService.shared
    @State private var googleAuth = GoogleAuthService.shared
    @State private var service = ExportService.shared
    @State private var connectError: String?
    @State private var showDisconnectConfirm = false
    @State private var showGoogleDisconnectConfirm = false
    @AppStorage(ExportService.autoExportKey) private var autoExport = false
    @AppStorage(NotificationService.doneNotificationKey) private var doneNotification = true
    @AppStorage(LiveTranscriber.Setting.storageKey) private var liveCaption = true

    var body: some View {
        NavigationStack {
            List {
                Section("연동") {
                    // Notion
                    Button {
                        if auth.isConnected {
                            showDisconnectConfirm = true
                        } else {
                            connect()
                        }
                    } label: {
                        HStack {
                            Text("Notion")
                                .foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                            Text(notionValueText)
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    // Google Docs (08-m5)
                    Button {
                        if googleAuth.isConnected {
                            showGoogleDisconnectConfirm = true
                        } else {
                            connectGoogle()
                        }
                    } label: {
                        HStack {
                            Text("Google Docs")
                                .foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                            Text(googleValueText)
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    Toggle(isOn: $autoExport) {
                        Text("정리 후 자동 내보내기")
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                    .tint(DesignTokens.accent)
                    .disabled(!auth.isConnected && !googleAuth.isConnected)
                }

                EngineSection()

                GlossarySection()

                StorageSection()

                defaultsSection

                if let connectError {
                    Section {
                        Text(connectError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .tint(DesignTokens.accent)
                }
            }
            .confirmationDialog("Notion 연결을 해제할까요?",
                                isPresented: $showDisconnectConfirm,
                                titleVisibility: .visible) {
                Button("연결 해제", role: .destructive) { auth.disconnect() }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("Google 연결을 해제할까요?",
                                isPresented: $showGoogleDisconnectConfirm,
                                titleVisibility: .visible) {
                Button("연결 해제", role: .destructive) { googleAuth.disconnect() }
                Button("취소", role: .cancel) {}
            }
        }
    }

    // MARK: - 기본값 섹션 (1h)

    private var defaultsSection: some View {
        Section("기본값") {
            // 회의 유형이 일반 하나로 정리돼 기본 유형 선택은 걷어냈다 (#21)
            Toggle(isOn: $doneNotification) {
                Text("처리 완료 알림")
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .tint(DesignTokens.accent)

            // 녹음 중 자막은 배터리를 더 쓴다 (D6). 기본은 켜 두고 끌 수 있게 했다.
            Toggle(isOn: $liveCaption) {
                Text("녹음 중 자막")
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .tint(DesignTokens.accent)

            // 요약이 실패했을 때 원인을 확인할 수 있는 통로 (#21)
            NavigationLink {
                SummaryDiagnosticsView()
            } label: {
                Text("요약 진단")
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            // 같은 오디오로 어휘 유무를 비교하는 자리 (#21 후속)
            NavigationLink {
                RetranscribeLabView()
            } label: {
                Text("전사 실험실")
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Link(destination: AppReviewSupport.privacyPolicyURL) {
                HStack {
                    Text("개인정보 처리방침")
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }

            HStack {
                Text("버전")
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                     as? String ?? "1.0")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }

    private var notionValueText: String {
        guard auth.isConnected else { return "연결 안 됨" }
        if let db = service.lastDatabaseName { return db }
        return auth.workspaceName ?? "연결됨"
    }

    private var googleValueText: String {
        guard googleAuth.isConnected else { return "연결 안 됨" }
        return service.lastFolderName ?? "연결됨"
    }

    private func connect() {
        connectError = nil
        Task {
            do {
                try await auth.connect()
            } catch {
                connectError = error.localizedDescription
            }
        }
    }

    private func connectGoogle() {
        connectError = nil
        Task {
            do {
                try await googleAuth.connect()
            } catch {
                connectError = error.localizedDescription
            }
        }
    }
}
