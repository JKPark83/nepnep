import SwiftData
import SwiftUI

/// 회의 상세 (와이어프레임 1e 확정본)
struct MeetingDetailView: View {
    @Query private var meetings: [Meeting]
    @State private var player = AudioPlayerController()
    @State private var showSpeakerSheet = false
    @State private var showExportSheet = false

    init(meetingID: UUID) {
        _meetings = Query(filter: #Predicate<Meeting> { $0.id == meetingID })
    }

    var body: some View {
        Group {
            if let meeting = meetings.first {
                content(meeting)
            } else {
                Text("회의를 찾을 수 없어요")
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .background(DesignTokens.background)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    private func content(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(meeting)
                SummaryTabView(meeting: meeting)
                transcriptSection(meeting)
            }
            .padding(.horizontal, DesignTokens.margin)
            .padding(.bottom, 120)   // 하단 고정 바 여백
        }
        .safeAreaInset(edge: .bottom) { bottomBar(meeting) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareSummaryMenu(meeting: meeting) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("요약 공유")
                .tint(DesignTokens.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSpeakerSheet = true
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("화자 이름 지정")
                .tint(DesignTokens.accent)
            }
        }
        .sheet(isPresented: $showSpeakerSheet) {
            SpeakerNamingSheet(meeting: meeting, player: player)
                .presentationDetents([.fraction(0.75)])
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(meeting: meeting)
        }
        .task { player.load(meeting: meeting) }
    }

    // MARK: - 헤더 (큰 제목 + 메타 + 아바타 스택)

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meeting.title)
                .font(.title.bold())
                .foregroundStyle(DesignTokens.textPrimary)
            HStack(spacing: 8) {
                Text(MeetingDateFormat.relative(meeting.createdAt))
                Text("·").opacity(0.5)
                Text(MeetingDateFormat.duration(meeting.duration))
                Text("·").opacity(0.5)
                Text(meeting.type.displayName)
            }
            .font(.footnote)
            .foregroundStyle(DesignTokens.textSecondary)
            avatarStack(meeting)
        }
        .padding(.top, 8)
    }

    /// 겹치는 아바타 스택 (1e: -7px 오버랩)
    private func avatarStack(_ meeting: Meeting) -> some View {
        HStack(spacing: -7) {
            ForEach(meeting.speakers.sorted(by: { $0.label < $1.label })) { speaker in
                SpeakerAvatarView(speaker: speaker, size: 30)
                    .overlay(Circle().stroke(DesignTokens.background, lineWidth: 2))
            }
        }
        .onTapGesture { showSpeakerSheet = true }
    }

    // MARK: - 전사

    private func transcriptSection(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("전사")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            TranscriptListView(meeting: meeting, player: player)
        }
    }

    // MARK: - 하단 고정 바 (플레이어 + 내보내기, 블러 배경 — 1e)

    private func bottomBar(_ meeting: Meeting) -> some View {
        VStack(spacing: 10) {
            if player.isActive {
                playerBar
            }
            Button {
                showExportSheet = true
            } label: {
                Text("내보내기")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.buttonHeight)
                    .background(meeting.status == .done
                        ? DesignTokens.accent : DesignTokens.accent.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(meeting.status != .done)
        }
        .padding(.horizontal, DesignTokens.margin)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.accent)
            }
            .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")
            Text(MeetingDateFormat.timestamp(player.currentTime))
                .font(.caption.monospaced())
                .foregroundStyle(DesignTokens.textSecondary)
            Slider(
                value: .init(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 1))
                .tint(DesignTokens.accent)
            Text(MeetingDateFormat.timestamp(player.duration))
                .font(.caption.monospaced())
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DesignTokens.card)
        .clipShape(Capsule())
    }
}
