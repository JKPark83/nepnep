import SwiftUI

/// 내보내기 시트 — 대상 선택 → 진행 → 완료 (와이어프레임 1g)
struct ExportSheet: View {
    let meeting: Meeting

    @Environment(\.dismiss) private var dismiss
    @State private var auth = NotionAuthService.shared
    @State private var googleAuth = GoogleAuthService.shared
    @State private var service = ExportService.shared
    @State private var selectedTarget: ExportTarget?
    @State private var showTargetPicker = false
    @State private var showFolderPicker = false
    @State private var connectError: String?
    @AppStorage(ExportService.autoExportKey) private var autoExport = false

    var body: some View {
        NavigationStack {
            Group {
                switch service.phase {
                case .idle:
                    targetStep
                case .running(let done, let total):
                    progressStep(done: done, total: total)
                case .done(let pageURL, let updated):
                    doneStep(pageURL: pageURL, updated: updated)
                case .failed(let message):
                    failedStep(message: message)
                }
            }
            .navigationTitle("내보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .tint(DesignTokens.accent)
                }
            }
            .navigationDestination(isPresented: $showTargetPicker) {
                NotionTargetPicker()
            }
            .navigationDestination(isPresented: $showFolderPicker) {
                GoogleFolderPicker()
            }
            .background(DesignTokens.background)
        }
        .onAppear { preselectTarget() }
    }

    /// 연결된 대상이 하나면 미리 선택, 둘 다면 마지막 사용 대상 (1g 노트 1)
    private func preselectTarget() {
        guard selectedTarget == nil else { return }
        let notionOn = auth.isConnected
        let googleOn = googleAuth.isConnected
        if let last = service.lastTarget,
           (last == .notion && notionOn) || (last == .google && googleOn) {
            selectedTarget = last
        } else if notionOn != googleOn {
            selectedTarget = notionOn ? .notion : .google
        }
    }

    // MARK: - 1단계: 대상 선택

    private var targetStep: some View {
        VStack(spacing: 16) {
            List {
                Section {
                    // Notion 행
                    Button {
                        if auth.isConnected {
                            selectedTarget = .notion
                        } else {
                            connect(.notion)
                        }
                    } label: {
                        targetRow(icon: "n.square",
                                  title: "Notion",
                                  subtitle: auth.isConnected
                                      ? "데이터베이스에 페이지로 추가"
                                      : "연결 안 됨 — 눌러서 연결",
                                  selected: selectedTarget == .notion)
                    }
                    if selectedTarget == .notion, auth.isConnected {
                        destinationRow(name: service.lastDatabaseName,
                                       placeholder: "선택 안 됨") {
                            showTargetPicker = true
                        }
                    }
                    // Google Docs 행 (08-m5)
                    Button {
                        if googleAuth.isConnected {
                            selectedTarget = .google
                        } else {
                            connect(.google)
                        }
                    } label: {
                        targetRow(icon: "doc.text",
                                  title: "Google Docs",
                                  subtitle: googleAuth.isConnected
                                      ? "지정 폴더에 문서로 생성"
                                      : "연결 안 됨 — 눌러서 연결",
                                  selected: selectedTarget == .google)
                    }
                    if selectedTarget == .google, googleAuth.isConnected {
                        // 폴더 미선택은 정상 상태 — 내 드라이브 최상위에 만든다
                        destinationRow(name: service.lastFolderName,
                                       placeholder: "내 드라이브 (기본)") {
                            showFolderPicker = true
                        }
                    }
                } footer: {
                    if let connectError {
                        Text(connectError).foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle(isOn: $autoExport) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("앞으로 자동으로 내보내기")
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text("정리가 끝나면 알림만 보내드려요")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .tint(DesignTokens.accent)
                }
            }
            .scrollContentBackground(.hidden)

            Button {
                startExport()
            } label: {
                Text("내보내기")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(canExport ? DesignTokens.accent : DesignTokens.accent.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canExport)
            .padding(.horizontal, DesignTokens.margin)
            .padding(.bottom, 12)
        }
        .background(DesignTokens.background)
    }

    private var canExport: Bool {
        ExportGate.canExport(target: selectedTarget,
                             notionConnected: auth.isConnected,
                             googleConnected: googleAuth.isConnected,
                             databaseID: service.lastDatabaseID)
    }

    private func startExport() {
        switch selectedTarget {
        case .notion:
            guard let databaseID = service.lastDatabaseID else {
                showTargetPicker = true
                return
            }
            service.export(meeting: meeting, databaseID: databaseID)
        case .google:
            // 폴더를 안 고른 채로도 진행한다 — 내 드라이브 최상위에 만들어진다
            service.exportGoogle(meeting: meeting, folderID: service.lastFolderID)
        case nil:
            break
        }
    }

    private func connect(_ target: ExportTarget) {
        connectError = nil
        Task {
            do {
                switch target {
                case .notion: try await auth.connect()
                case .google: try await googleAuth.connect()
                }
                selectedTarget = target
            } catch {
                connectError = error.localizedDescription
            }
        }
    }

    // MARK: - 2단계: 진행

    private func progressStep(done: Int, total: Int) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(DesignTokens.accent)
                .padding(.horizontal, 48)
            Text(service.runningTarget == .google
                 ? "Google Docs로 내보내는 중"
                 : "Notion으로 내보내는 중")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(service.runningTarget == .google
                 ? "\(service.lastFolderName ?? "내 드라이브") · 문서 작성 중"
                 : "\(service.lastDatabaseName ?? "데이터베이스") · 블록 \(done) / \(total) 작성")
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
            Text("시트를 닫아도 내보내기는 계속돼요")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Button("취소") { service.cancel() }
                .foregroundStyle(.red)
                .padding(.bottom, 24)
        }
    }

    // MARK: - 3단계: 완료 / 실패

    private func doneStep(pageURL: String, updated: Bool) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(DesignTokens.accent)
            Text(updated
                 ? (service.runningTarget == .google ? "기존 문서를 갱신했어요" : "기존 페이지를 갱신했어요")
                 : (service.runningTarget == .google ? "Google Docs에 저장했어요" : "Notion에 저장했어요"))
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.textPrimary)
            Text("\(destinationName) · \(MeetingDateFormat.relative(meeting.createdAt))")
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
            if let url = URL(string: pageURL) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text(service.runningTarget == .google ? "Docs에서 열기" : "Notion에서 열기")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, DesignTokens.margin)
                .padding(.top, 12)
            }
            Spacer()
        }
        .onDisappear { service.reset() }
    }

    private func failedStep(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("내보내기에 실패했어요")
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                service.reset()
            } label: {
                Text("다시 시도")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, DesignTokens.margin)
            .padding(.top, 12)
            Spacer()
        }
    }

    private var destinationName: String {
        service.runningTarget == .google
            ? (service.lastFolderName ?? "내 드라이브")
            : (service.lastDatabaseName ?? "데이터베이스")
    }

    // MARK: - 공통 행

    private func targetRow(icon: String, title: String,
                           subtitle: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.accent)
            }
        }
    }

    private func destinationRow(name: String?, placeholder: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("대상")
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text(name ?? placeholder)
                    .foregroundStyle(DesignTokens.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }
}
