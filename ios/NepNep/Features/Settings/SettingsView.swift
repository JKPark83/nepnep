import SwiftUI

/// 설정 — 연동(M4) + 구독·사용량(M5) 섹션 (와이어프레임 1h)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = NotionAuthService.shared
    @State private var googleAuth = GoogleAuthService.shared
    @State private var service = ExportService.shared
    @State private var purchase = PurchaseService.shared
    @State private var usage = UsageTracker.shared
    @State private var connectError: String?
    @State private var showDisconnectConfirm = false
    @State private var showGoogleDisconnectConfirm = false
    @State private var showPaywall = false
    @AppStorage(ExportService.autoExportKey) private var autoExport = false
    @AppStorage(MeetingType.defaultKey) private var defaultTypeRaw = MeetingType.general.rawValue
    @AppStorage(NotificationService.doneNotificationKey) private var doneNotification = true

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

                subscriptionSection

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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                if purchase.isPro {
                    await CloudPipelineClient.shared.refreshUsage()
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
            Picker(selection: $defaultTypeRaw) {
                ForEach(MeetingType.allCases, id: \.rawValue) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            } label: {
                Text("기본 회의 유형")
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .tint(DesignTokens.textSecondary)

            Toggle(isOn: $doneNotification) {
                Text("처리 완료 알림")
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .tint(DesignTokens.accent)

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

    // MARK: - 구독 섹션 (1h)

    private var subscriptionSection: some View {
        Section("구독") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(purchase.isPro ? "프로 플랜" : "무료 플랜")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(purchase.isPro ? "월 20시간" : "온디바이스 무제한")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DesignTokens.textSecondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Text(purchase.isPro
                     ? "클라우드 고품질 처리를 사용할 수 있어요"
                     : "클라우드 고품질 처리는 프로에서 사용할 수 있어요")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.vertical, 4)

            // 무료 사용자에게도 사용량 행 노출 (1h 노트 2)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("이번 달 클라우드 사용")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Text(UsageTracker.usageText(usedSeconds: usage.usedSeconds))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                ProgressView(value: usage.usedSeconds,
                             total: UsageTracker.monthlyLimitSeconds)
                    .tint(DesignTokens.accent)
                Text("매월 1일 초기화")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary.opacity(0.7))
            }
            .padding(.vertical, 4)

            if !purchase.isPro {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Text("프로 자세히 보기")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.bold())
                    }
                    .foregroundStyle(DesignTokens.accent)
                }
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
