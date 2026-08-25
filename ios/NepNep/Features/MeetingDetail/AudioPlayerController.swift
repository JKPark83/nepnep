import AVFoundation
import Foundation

/// 상세 화면 인라인 재생 (와이어프레임 1e·1f)
@MainActor
@Observable
final class AudioPlayerController {
    private var player: AVAudioPlayer?
    private var timer: Timer?

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    /// 한 번이라도 재생을 시작했는지 — 플레이어 바 노출 조건
    var isActive = false

    func load(meeting: Meeting) {
        guard player == nil else { return }
        guard let fileName = meeting.audioFileName else { return }
        let url = AudioFileStore.container.appendingPathComponent(fileName)
        guard let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
        loaded.prepareToPlay()
        player = loaded
        duration = loaded.duration
    }

    /// 발화 탭 → 해당 시점부터 재생 (F5-3)
    func play(from time: TimeInterval) {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = min(time, max(0, player.duration - 0.1))
        player.play()
        isActive = true
        isPlaying = true
        currentTime = player.currentTime
        startTimer()
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            play(from: player.currentTime)
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        isPlaying = false
        isActive = false
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.timer?.invalidate()
                }
            }
        }
    }
}
