import BackgroundTasks
import Foundation
import SwiftData

/// 파이프라인 오케스트레이션 + BGContinuedProcessingTask (03-m2 §4, F10-1·2·3)
@MainActor
@Observable
final class ProcessingCoordinator {
    static let shared = ProcessingCoordinator()
    static let taskIdentifier = "com.nepnep.processing.continued"

    var modelContext: ModelContext?
    /// 실행 대기 중인 회의 (제출 순서 유지)
    private var pendingMeetingIDs: [UUID] = []
    private var isRunning = false
    private var expired = false
    /// 시스템이 승인해 준 백그라운드 연장 태스크 (없어도 실행은 진행)
    private var currentBGTask: BGContinuedProcessingTask?
    /// 포그라운드 실행이 끝날 때까지 BG 태스크 핸들러를 붙잡아 두는 continuation
    private var bgTaskWaiter: CheckedContinuation<Void, Never>?

    // MARK: - 등록 (앱 런치 완료 전에 1회)

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil) { task in
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    await ProcessingCoordinator.shared.adopt(bgTask: task)
                }
            }
    }

    // MARK: - 진입점

    /// 정지 직후 RecordingSession.stop에서 호출.
    /// 실행은 항상 즉시 시작한다 — BG 태스크는 승인되면 백그라운드 연장에만 쓴다.
    /// (실기기에서 submit 성공 후에도 태스크 launch가 큐잉돼 시작이 지연될 수 있어,
    ///  핸들러 안에서만 실행을 시작하면 "대기 중 0%"에 멈춘다)
    func enqueue(meeting: Meeting) {
        meeting.status = .processing
        meeting.processingStage = "대기 중"
        meeting.processingProgress = 0
        try? modelContext?.save()
        pendingMeetingIDs.append(meeting.id)

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.taskIdentifier,
            title: "회의록 정리 중",
            subtitle: meeting.title)
        try? BGTaskScheduler.shared.submit(request)   // 실패해도 무방 — 아래에서 즉시 실행

        Task { await runPending() }
    }

    /// 시스템이 BG 태스크를 실행해 줬을 때 — 진행 중 실행에 부착하거나 새로 시작
    private func adopt(bgTask: BGContinuedProcessingTask) async {
        guard bgTaskWaiter == nil else {
            // 이미 다른 BG 태스크가 실행을 연장 중 → 중복 태스크는 즉시 반환
            bgTask.setTaskCompleted(success: true)
            return
        }
        currentBGTask = bgTask
        bgTask.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expired = true }
        }
        if isRunning {
            // 이미 실행 중 → 실행이 끝날 때까지 핸들러를 유지해 백그라운드 시간을 확보
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                bgTaskWaiter = c
            }
        } else {
            await runPending()
        }
        bgTask.setTaskCompleted(success: !expired)
        if currentBGTask === bgTask { currentBGTask = nil }
    }

    /// 포그라운드 복귀 시 미완료 회의 스캔 → 재-enqueue (F10-2 "다음 실행 시 재개")
    func resumeUnfinishedIfNeeded() {
        guard let context = modelContext, !isRunning else { return }
        let raw = MeetingStatus.processing.rawValue
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.statusRaw == raw })
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for meeting in stuck where !pendingMeetingIDs.contains(meeting.id) {
            enqueue(meeting: meeting)
        }
    }

    // MARK: - 실행

    private func runPending() async {
        guard !isRunning else { return }
        isRunning = true
        expired = false
        defer {
            isRunning = false
            bgTaskWaiter?.resume()   // 부착돼 있던 BG 태스크 핸들러 해제
            bgTaskWaiter = nil
        }

        while !pendingMeetingIDs.isEmpty {
            if expired { break }   // 체크포인트는 단계별로 이미 저장됨 → 다음 포그라운드에서 재개
            let id = pendingMeetingIDs.removeFirst()
            await process(meetingID: id)
        }
    }

    private func process(meetingID: UUID) async {
        guard let context = modelContext,
              let meeting = fetchMeeting(id: meetingID, context: context) else { return }

        let audioURL = AudioFileStore.mergedCafURL(meetingID: meetingID)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            fail(meeting, reason: .engineError)
            return
        }

        let engine = SpeechTranscriberEngine()

        let runner = PipelineRunner(
            engine: engine,
            diarizer: DiarizationService(),
            checkpoint: ProcessingCheckpoint(meetingID: meetingID))

        do {
            let utterances = try await runner.run(audioURL: audioURL) { stage in
                Task { @MainActor in
                    self.updateProgress(meeting: meeting, stage: stage)
                }
            }
            try save(utterances: utterances, to: meeting, context: context)
            try await finishAudio(meeting: meeting)
            await summarizeIfPossible(meeting: meeting, context: context)
            ProcessingCheckpoint(meetingID: meetingID).clear()
            meeting.status = .done
            meeting.processingStage = nil
            meeting.processingProgress = 1
            try? context.save()
            NotificationService.notifyDone(meeting: meeting)
            PhoneWatchSession.shared.pushContext()   // 워치 목록에도 결과 반영 (이슈 #15 §5)
            autoExportIfEnabled(meeting: meeting)
        } catch {
            fail(meeting, reason: .engineError)
        }
    }

    /// 정리 후 자동 내보내기 (06-m4 §4, 08-m5 §3 — 연결된 모든 대상 순차)
    private func autoExportIfEnabled(meeting: Meeting) {
        guard UserDefaults.standard.bool(forKey: ExportService.autoExportKey) else { return }
        ExportService.shared.autoExportAll(meeting: meeting)
    }

    // MARK: - 결과 반영

    private func save(utterances: [MergedUtterance],
                      to meeting: Meeting,
                      context: ModelContext) throws {
        // 재처리 대비: 기존 산출물 제거
        meeting.utterances.removeAll()
        meeting.speakers.removeAll()

        var speakerByKey: [String: Speaker] = [:]
        for (i, key) in TranscriptMerger.speakerKeysInOrder(utterances).enumerated() {
            let speaker = Speaker(label: "화자 \(i + 1)", colorIndex: i % 8)
            speakerByKey[key] = speaker
            meeting.speakers.append(speaker)
        }
        for (i, u) in utterances.enumerated() {
            guard let speaker = speakerByKey[u.speakerKey] else { continue }
            meeting.utterances.append(Utterance(
                speakerID: speaker.id, text: u.text,
                startTime: u.start, endTime: u.end,
                confidence: u.confidence, orderIndex: i))
        }
        try context.save()
    }

    /// 성공 후 CAF→m4a, CAF 삭제, audioSize 갱신 (00-overview "오디오 저장 포맷")
    private func finishAudio(meeting: Meeting) async throws {
        let caf = AudioFileStore.mergedCafURL(meetingID: meeting.id)
        let m4a = AudioFileStore.m4aURL(meetingID: meeting.id)
        try await AudioTranscoder.transcode(caf: caf, to: m4a)
        try? FileManager.default.removeItem(at: caf)
        meeting.audioFileName = "audio/\(meeting.id.uuidString)/recording.m4a"
        meeting.audioSize = AudioFileStore.fileSize(at: m4a)
    }

    /// 요약 실패·비가용은 처리 전체를 실패로 만들지 않는다 (05-m3 §4)
    private func summarizeIfPossible(meeting: Meeting,
                                     context: ModelContext) async {
        guard SummaryService.isAvailable else {
            meeting.summaryUnavailable = true
            return
        }
        updateProgress(meeting: meeting, stage: .summarizing(0))
        do {
            try await SummaryService.generate(meeting: meeting,
                                              type: meeting.type,
                                              context: context) { p in
                Task { @MainActor in
                    self.updateProgress(meeting: meeting, stage: .summarizing(p))
                }
            }
        } catch {
            meeting.summaryUnavailable = true
        }
    }

    private func updateProgress(meeting: Meeting,
                                stage: PipelineRunner.StageProgress) {
        // 전체 진행률 배분: 전사 0~0.55, 화자분리 0.55~0.75, 병합 0.75~0.8, 요약 0.8~1
        switch stage {
        case .transcribing(let p):
            meeting.processingStage = "받아쓰는 중"
            meeting.processingProgress = p * 0.55
        case .diarizing:
            meeting.processingStage = "화자를 나누는 중"
            meeting.processingProgress = 0.55
        case .merging:
            meeting.processingStage = "정리하는 중"
            meeting.processingProgress = 0.75
        case .summarizing(let p):
            meeting.processingStage = "요약하는 중"
            meeting.processingProgress = 0.8 + p * 0.2
        }
        if let bgTask = currentBGTask {
            bgTask.progress.totalUnitCount = 100
            bgTask.progress.completedUnitCount = Int64(meeting.processingProgress * 100)
        }
    }

    private func fail(_ meeting: Meeting, reason: ProcessingFailureReason) {
        // 전사·화자분리 산출물(체크포인트)은 보존 (F5-4 대비)
        meeting.status = .failed
        meeting.failureReasonRaw = reason.rawValue
        meeting.processingStage = nil
        try? modelContext?.save()
        NotificationService.notifyFailed(meeting: meeting)
        PhoneWatchSession.shared.pushContext()   // 워치 목록에도 실패 반영 (이슈 #15 §5)
    }

    private func fetchMeeting(id: UUID, context: ModelContext) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
}
