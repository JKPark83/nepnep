import AVFoundation

/// 16kHz mono Int16 CAF를 5분(300초) 단위 청크로 순차 기록한다 (02-m1 §3).
/// write는 전용 직렬 큐에서 실행 — 크래시 시 마지막 버퍼(≤수백 ms)만 잃는다.
final class ChunkedAudioWriter {
    static let sampleRate: Double = 16_000
    static let chunkDuration: TimeInterval = 300

    static var fileFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16,
                      sampleRate: sampleRate,
                      channels: 1,
                      interleaved: true)!
    }

    private let meetingID: UUID
    private let queue = DispatchQueue(label: "com.nepnep.audio-writer")
    private var currentFile: AVAudioFile?
    private var chunkIndex = 0
    private var framesInCurrentChunk: AVAudioFramePosition = 0
    private var framesPerChunk: AVAudioFramePosition {
        AVAudioFramePosition(Self.chunkDuration * Self.sampleRate)
    }

    init(meetingID: UUID) {
        self.meetingID = meetingID
    }

    /// 변환 완료된 16kHz mono Int16 버퍼를 기록한다.
    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            do {
                if currentFile == nil || framesInCurrentChunk >= framesPerChunk {
                    try rotateFile()
                }
                try currentFile?.write(from: buffer)
                framesInCurrentChunk += AVAudioFramePosition(buffer.frameLength)
            } catch {
                // 기록 실패는 다음 버퍼에서 재시도된다. 반복 실패 시 정지 단계에서 드러난다.
            }
        }
    }

    /// 남은 기록을 마치고 청크들을 recording.caf로 병합한 뒤 청크를 삭제한다.
    func finishAndMerge() throws -> URL {
        queue.sync { currentFile = nil }   // 파일 닫기 (마지막 write 플러시 대기)
        return try Self.mergeChunks(meetingID: meetingID)
    }

    private func rotateFile() throws {
        try AudioFileStore.createDirectory(for: meetingID)
        let url = AudioFileStore.chunkURL(meetingID: meetingID, index: chunkIndex)
        currentFile = try AVAudioFile(
            forWriting: url,
            settings: Self.fileFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true)
        chunkIndex += 1
        framesInCurrentChunk = 0
    }

    /// 청크 순차 read→write 병합. 크래시 복구(F1-4) 경로에서도 재사용한다.
    static func mergeChunks(meetingID: UUID) throws -> URL {
        let chunks = AudioFileStore.chunkURLs(meetingID: meetingID)
        let mergedURL = AudioFileStore.mergedCafURL(meetingID: meetingID)
        guard !chunks.isEmpty else {
            if FileManager.default.fileExists(atPath: mergedURL.path) { return mergedURL }
            throw NSError(domain: "ChunkedAudioWriter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "병합할 청크가 없습니다"])
        }

        let output = try AVAudioFile(
            forWriting: mergedURL,
            settings: fileFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true)

        for chunkURL in chunks {
            let input = try AVAudioFile(forReading: chunkURL,
                                        commonFormat: .pcmFormatInt16,
                                        interleaved: true)
            let capacity: AVAudioFrameCount = 65_536
            let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat,
                                          frameCapacity: capacity)!
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
        }

        for chunkURL in chunks {
            try? FileManager.default.removeItem(at: chunkURL)
        }
        return mergedURL
    }
}
