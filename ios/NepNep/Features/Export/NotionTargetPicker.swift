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
            } else if databases.isEmpty {
                Text("접근 가능한 데이터베이스가 없어요.\nNotion에서 통합에 데이터베이스를 공유해 주세요.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.textSecondary)
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
        .task { await load() }
    }

    private func load() async {
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
