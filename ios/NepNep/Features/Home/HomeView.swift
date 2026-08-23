import SwiftData
import SwiftUI

/// 홈 (와이어프레임 1b 확정본)
struct HomeView: View {
    /// 2단 레이아웃의 사이드바로 쓰일 때만 true — 상세 칼럼이 보고 있는 회의를 표시한다.
    /// 사이드바 칼럼 안에서는 폭이 좁아 horizontalSizeClass가 compact로 내려오므로
    /// 사이즈 클래스로는 2단인지 알 수 없다. 레이아웃을 아는 쪽에서 내려준다.
    var showsSelection = false

    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]
    @State private var store = MeetingStore()
    /// 아이패드 2단에서 상세 칼럼이 무엇을 보여주는지 알아야 선택 표시를 그릴 수 있다
    @State private var router = Router.shared
    @State private var recordingLaunch: RecordingLaunch?
    @State private var processingTarget: Meeting?
    @State private var renameTarget: Meeting?
    @State private var renameText = ""
    @State private var showSettings = false

    /// 홈에 노출할 회의 (recording 상태는 녹음 화면이 담당)
    private var meetings: [Meeting] {
        store.filtered(allMeetings.filter { $0.status != .recording })
    }

    private var recoveredMeetings: [Meeting] {
        allMeetings.filter { $0.status == .recorded }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                brandHeader
                if ModelAssetManager.shared.isPreparingAssets {
                    assetPreparingBanner
                }
                if allMeetings.contains(where: { $0.status != .recording }) {
                    meetingList
                        .searchable(text: $store.searchText,
                                    prompt: "회의 제목 · 내용 검색")
                } else {
                    emptyState
                }
            }
            fabLayer
        }
        .background(DesignTokens.background)
        // 이름은 아래 brandHeader가 그린다 — 내비게이션 바에는 검색·아이콘만 남긴다
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("설정")
                .tint(DesignTokens.accent)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $recordingLaunch) { launch in
            RecordingFlowView(initialType: launch.type)
        }
        .fullScreenCover(item: $processingTarget) { meeting in
            ProcessingView(meeting: meeting)
        }
        .alert("제목 변경", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField("회의 제목", text: $renameText)
            Button("저장") {
                if let target = renameTarget, !renameText.isEmpty {
                    target.title = renameText
                    try? context.save()
                }
                renameTarget = nil
            }
            Button("취소", role: .cancel) { renameTarget = nil }
        }
    }

    // MARK: - 앱 이름 영역 (와이어프레임 2b 타이포 락업 + 2a 마크)

    private var brandHeader: some View {
        BrandLockupView()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.margin)
            .padding(.top, 4)
            .padding(.bottom, 14)
    }

    // MARK: - 목록

    private var meetingList: some View {
        List {
            if !recoveredMeetings.isEmpty {
                recoveryBanner
                    .listRowStyle()
            }
            ForEach(meetings) { meeting in
                MeetingCardView(meeting: meeting) {
                    ProcessingCoordinator.shared.enqueue(meeting: meeting)
                    processingTarget = meeting
                }
                .contentShape(Rectangle())
                .onTapGesture { open(meeting) }
                .overlay {
                    if isSelected(meeting) {
                        RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
                            .strokeBorder(DesignTokens.accent, lineWidth: 2)
                    }
                }
                .listRowStyle()
                .swipeActions(edge: .trailing) {
                    Button("삭제", role: .destructive) {
                        store.delete(meeting, context: context)
                    }
                    Button("제목 변경") {
                        renameText = meeting.title
                        renameTarget = meeting
                    }
                    .tint(DesignTokens.accent)
                }
            }
            // FAB에 가리지 않도록 하단 여백
            Color.clear.frame(height: DesignTokens.fabSize + 40)
                .listRowStyle()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// 아이패드 2단에서만 표시한다 — 아이폰은 상세로 밀고 들어가니 선택 개념이 없다
    private func isSelected(_ meeting: Meeting) -> Bool {
        showsSelection && router.path.last == meeting.id
    }

    private func open(_ meeting: Meeting) {
        switch meeting.status {
        case .done:
            Router.shared.openMeeting(meeting.id)
        case .processing, .failed:
            processingTarget = meeting
        case .recorded:
            ProcessingCoordinator.shared.enqueue(meeting: meeting)
            processingTarget = meeting
        case .recording:
            break
        case .pendingTransfer:
            // 오디오가 아직 도착하지 않아 열어 볼 것이 없다. 카드 본문이 이유를 설명한다.
            break
        }
    }

    /// 모델 프리웜 진행 배너 — 다운로드 중에만 표시
    private var assetPreparingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("음성 인식 모델을 준비하고 있어요")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DesignTokens.card)
    }

    /// 크래시 복구된 녹음 배너 (02-m1 §5 → 홈 노출은 M2-B)
    private var recoveryBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(DesignTokens.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("복구된 녹음이 있어요")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("앱이 갑자기 종료됐지만 녹음은 안전하게 저장됐어요")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
            Button("정리하기") {
                for meeting in recoveredMeetings {
                    ProcessingCoordinator.shared.enqueue(meeting: meeting)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DesignTokens.accent)
        }
        .padding(16)
        .background(DesignTokens.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    // MARK: - 빈 상태 (1b 노트: 검색 필드 숨김)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mic.circle")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
            Text("첫 회의를 녹음해 보세요")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            Text("녹음이 끝나면 전사와 화자 구분까지 자동으로 정리돼요")
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text("여기서 시작")
                .font(.footnote)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.bottom, DesignTokens.fabSize + 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - FAB (68pt, 길게 눌러 유형 선택 — 1b 노트)

    private var fabLayer: some View {
        VStack {
            Spacer()
            Menu {
                ForEach(MeetingType.allCases, id: \.self) { type in
                    Button(type.displayName) {
                        recordingLaunch = RecordingLaunch(type: type)
                    }
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .frame(width: DesignTokens.fabSize, height: DesignTokens.fabSize)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            } primaryAction: {
                recordingLaunch = RecordingLaunch(type: MeetingType.defaultType)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // 하단 그라데이션 배경 (1b)
            LinearGradient(
                colors: [DesignTokens.background.opacity(0), DesignTokens.background],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)
        }
    }
}

/// fullScreenCover(item:)용 래퍼
private struct RecordingLaunch: Identifiable {
    let id = UUID()
    let type: MeetingType
}

private extension View {
    /// 카드 리스트 공통 행 스타일
    func listRowStyle() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: DesignTokens.margin,
                                      bottom: 6, trailing: DesignTokens.margin))
    }
}
