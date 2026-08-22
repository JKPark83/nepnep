import SwiftUI

/// 대상 데이터베이스 선택 (와이어프레임 1g 대상 행 → 푸시)
struct NotionTargetPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var databases: [NotionDatabase] = []
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                recoveryActions
            } else if databases.isEmpty {
                Section {
                    Text("접근 가능한 데이터베이스가 없어요.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("""
                    회의록을 저장할 데이터베이스를 넵넵에 공유해야 목록에 떠요.
                    1. 아래 '권한 다시 선택'을 눌러 Notion 권한 화면을 엽니다.
                    2. 데이터베이스가 들어 있는 페이지를 골라 허용합니다.
                    이미 허용했다면 Notion 앱에서 데이터베이스 우측 상단 ··· → \
                    연결 → 넵넵을 추가한 뒤 '다시 불러오기'를 눌러 주세요.
                    """)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                recoveryActions
            } else {
                ForEach(databases) { database in
                    Button {
                        ExportService.shared.rememberDatabase(database)
                        dismiss()
                    } label: {
                        HStack {
                            Text(database.title)
                                .foregroundStyle(DesignTokens.textPrimary)
                            Spacer()
                            if database.id == ExportService.shared.lastDatabaseID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignTokens.accent)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.background)
        .navigationTitle("대상 선택")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    /// 빈 목록·오류에서 빠져나갈 두 가지 길 (재연동 / 다시 불러오기)
    private var recoveryActions: some View {
        Section {
            Button { reconnect() } label: {
                Label("Notion에서 권한 다시 선택", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(DesignTokens.accent)
            }
            Button { Task { await load() } } label: {
                Label("다시 불러오기", systemImage: "arrow.clockwise")
                    .foregroundStyle(DesignTokens.accent)
            }
        }
    }

    /// 권한 화면을 다시 띄우고, 끝나면 목록을 즉시 새로 읽는다
    private func reconnect() {
        Task {
            do {
                try await NotionAuthService.shared.connect()
            } catch NotionAuthService.AuthError.cancelled {
                return
            } catch {
                loadError = error.localizedDescription
                return
            }
            await load()
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        guard let token = NotionAuthService.shared.token else {
            loadError = NotionAPIError.unauthorized.localizedDescription
            isLoading = false
            return
        }
        do {
            databases = try await NotionAPIClient(token: token).searchDatabases()
        } catch NotionAPIError.unauthorized {
            NotionAuthService.shared.disconnect()
            loadError = NotionAPIError.unauthorized.localizedDescription
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
