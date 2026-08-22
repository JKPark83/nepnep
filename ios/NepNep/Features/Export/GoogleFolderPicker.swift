import SwiftUI

/// Drive 폴더 선택 (08-m5 §2, 와이어프레임 1g 대상 행 → 푸시)
/// drive.file scope라 앱이 만든·사용자가 이 앱에서 고른 폴더만 보인다.
struct GoogleFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [GoogleDocsClient.DriveFolder] = []
    @State private var searchText = ""
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
            } else {
                // 폴더를 고르지 않는 것도 정식 선택지다 — drive.file scope라
                // 목록이 늘 비어 있을 수 있어 이 행이 사실상 기본 경로다.
                Section {
                    Button {
                        ExportService.shared.forgetFolder()
                        dismiss()
                    } label: {
                        row(icon: "externaldrive",
                            name: "내 드라이브 최상위",
                            selected: ExportService.shared.lastFolderID == nil)
                    }
                } footer: {
                    Text(folders.isEmpty
                         ? "표시할 폴더가 없어요. 이 앱에서 만들거나 고른 폴더만 보여요."
                         : "고르지 않으면 내 드라이브 최상위에 만들어져요.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                ForEach(folders) { folder in
                    Button {
                        ExportService.shared.rememberFolder(id: folder.id, name: folder.name)
                        dismiss()
                    } label: {
                        row(icon: "folder",
                            name: folder.name,
                            selected: folder.id == ExportService.shared.lastFolderID)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.background)
        .navigationTitle("폴더 선택")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "폴더 이름 검색")
        .task { await load() }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func row(icon: String, name: String, selected: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.accent)
            Text(name)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(DesignTokens.accent)
            }
        }
    }

    private func load() async {
        do {
            let token = try await GoogleAuthService.shared.validAccessToken()
            folders = try await GoogleDocsClient(token: token).listFolders(nameQuery: searchText)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
