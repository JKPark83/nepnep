import SwiftUI
import UIKit

/// 녹음 화면 (02-m1 §7, 와이어프레임 1c 확정본)
struct RecordingView: View {
    var initialType: MeetingType = .general
    /// 완료로 정지했을 때 호출 — 처리 화면(1d) 전환 (RecordingFlowView)
    var onFinished: (Meeting) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var session = RecordingSession.shared
    @State private var meetingType: MeetingType = .general
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var finishedMeeting: Meeting?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            titleSection
            typeSegment
                .padding(.top, 16)
            elapsedTimer
                .padding(.top, 40)
            LevelMeterView(levelDB: session.levelDB)
                .frame(height: 44)
                .padding(.horizontal, DesignTokens.margin)
                .padding(.top, 24)
            silenceHint
            Spacer()
            controls
                .padding(.vertical, 32)
        }
        .background(DesignTokens.background)
        .task {
            if session.state == .idle {
                meetingType = initialType
                await session.start(type: initialType)
            }
        }
        .onChange(of: session.state) { _, newState in
            // 정지 완료(handoff→idle): 완료 정지면 처리 화면(1d)으로, 그 외엔 닫기
            if newState == .idle, session.currentMeeting == nil {
                if let meeting = finishedMeeting {
                    onFinished(meeting)
                } else {
                    dismiss()
                }
            }
        }
        .alert("4시간이 되어 녹음을 마쳤어요", isPresented: $session.didAutoStop) {
            Button("확인") { dismiss() }
        }
        .alert("녹음 오류", isPresented: .constant(session.errorMessage != nil)) {
            // 마이크 권한 거부 → 설정 앱 유도 (09-m6 §1)
            if session.errorMessage?.contains("마이크") == true,
               let url = URL(string: UIApplication.openSettingsURLString) {
                Button("설정 열기") {
                    session.errorMessage = nil
                    UIApplication.shared.open(url)
                    dismiss()
                }
            }
            Button("확인") {
                session.errorMessage = nil
                if session.state == .idle { dismiss() }
            }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: - 구성 요소

    private var header: some View {
        HStack {
            Button("취소") {
                session.stop()   // 임시: M2에서 "저장 없이 폐기" 확인 알럿 추가
                dismiss()
            }
            .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            Text(session.state == .pausedByUser || session.state == .pausedByInterruption
                 ? "일시정지됨" : "녹음 중")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
            // 좌우 균형용 투명 버튼
            Button("취소") {}.hidden()
        }
        .padding(.horizontal, DesignTokens.margin)
        .padding(.top, 12)
    }

    private var titleSection: some View {
        HStack(spacing: 8) {
            Text(session.currentMeeting?.title ?? Meeting.autoTitle(type: meetingType))
                .font(.title2.bold())
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Button {
                editedTitle = session.currentMeeting?.title ?? ""
                isEditingTitle = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(.horizontal, DesignTokens.margin)
        .alert("제목 수정", isPresented: $isEditingTitle) {
            TextField("회의 제목", text: $editedTitle)
            Button("저장") {
                if !editedTitle.isEmpty {
                    session.currentMeeting?.title = editedTitle
                }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var typeSegment: some View {
        Picker("회의 유형", selection: $meetingType) {
            ForEach(MeetingType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignTokens.margin)
        .onChange(of: meetingType) { _, newType in
            // 유형 변경 즉시 반영 (F1-7). 자동 제목이면 제목도 갱신.
            guard let meeting = session.currentMeeting else { return }
            let wasAuto = meeting.title == Meeting.autoTitle(type: meeting.type,
                                                            date: meeting.createdAt)
            meeting.type = newType
            if wasAuto {
                meeting.title = Meeting.autoTitle(type: newType, date: meeting.createdAt)
            }
        }
    }

    private var elapsedTimer: some View {
        Text(Duration.seconds(session.elapsed),
             format: .time(pattern: .minuteSecond))
            .font(.system(size: 64, weight: .medium, design: .monospaced))
            .foregroundStyle(DesignTokens.textPrimary)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private var silenceHint: some View {
        if session.silenceSeconds >= 30 {
            Text("소리가 들리지 않아요")
                .font(.footnote)
                .foregroundStyle(DesignTokens.statusProcessing)
                .padding(.top, 8)
        }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            // 일시정지 중에는 중앙 버튼이 재개로 바뀐다 (1c 노트 4)
            Button {
                if session.state == .recording {
                    session.pause()
                } else {
                    session.resume()
                }
            } label: {
                Image(systemName: session.state == .recording ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: DesignTokens.fabSize, height: DesignTokens.fabSize)
                    .background(DesignTokens.card)
                    .clipShape(Circle())
            }
            .foregroundStyle(DesignTokens.textPrimary)

            Button {
                finishedMeeting = session.currentMeeting
                session.stop()
            } label: {
                Text("완료")
                    .font(.headline)
                    .frame(width: 120, height: DesignTokens.buttonHeight)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}

/// 레벨 미터 — 입력 신호만 시각화, 파형 저장 없음 (1c 노트 2)
struct LevelMeterView: View {
    let levelDB: Float
    private let barCount = 24

    var body: some View {
        // -60dB…0dB → 0…1
        let norm = max(0, min(1, (levelDB + 60) / 60))
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                let threshold = Float(i) / Float(barCount)
                Capsule()
                    .fill(norm > threshold
                          ? DesignTokens.accent
                          : DesignTokens.textSecondary.opacity(0.25))
                    .frame(maxHeight: .infinity)
            }
        }
        .animation(.linear(duration: 0.1), value: norm)
    }
}
