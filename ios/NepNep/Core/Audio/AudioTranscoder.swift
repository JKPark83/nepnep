import AVFoundation

/// CAF(PCM) → m4a(AAC 32kbps mono) 트랜스코드 (02-m1 §산출물, 호출은 M2 파이프라인 끝에서)
enum AudioTranscoder {
    static func transcode(caf source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioTranscoder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "오디오 트랙이 없습니다"])
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
        ])
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ])
        writer.add(writerInput)

        guard reader.startReading() else { throw reader.error ?? readerFailure() }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.nepnep.transcoder")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sample)
                    } else {
                        writerInput.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? readerFailure()
        }
    }

    /// m4a(AAC) → 파이프라인 입력용 CAF(16kHz mono Int16).
    /// 워치가 보내온 오디오를 아이폰 녹음과 **똑같은 형태**로 만들어 놓는 용도다 —
    /// 이래야 `ProcessingCoordinator` 아래로는 워치에서 왔는지 여부를 알 필요가 없다.
    static func decodeToPipelineCAF(source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let outputFormat = ChunkedAudioWriter.fileFormat

        guard let converter = AVAudioConverter(from: input.processingFormat, to: outputFormat) else {
            throw NSError(domain: "AudioTranscoder", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "포맷 변환기 생성 실패"])
        }

        try? FileManager.default.removeItem(at: destination)
        let output = try AVAudioFile(
            forWriting: destination,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true)

        let inputCapacity: AVAudioFrameCount = 16_384
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat,
                                                 frameCapacity: inputCapacity) else {
            throw NSError(domain: "AudioTranscoder", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "입력 버퍼 생성 실패"])
        }
        // 업샘플링이면 출력이 입력보다 길어진다. 여유를 두지 않으면 변환이 잘린다.
        let ratio = outputFormat.sampleRate / input.processingFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputCapacity) * max(ratio, 1)) + 1_024

        var reachedEnd = false
        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                      frameCapacity: outputCapacity) else { break }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if reachedEnd {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                // 파일 끝에서는 예외가 아니라 frameLength 0으로 돌아온다
                do {
                    try input.read(into: inputBuffer)
                } catch {
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if inputBuffer.frameLength == 0 {
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inputBuffer
            }
            if let error { throw error }
            if outputBuffer.frameLength > 0 {
                try output.write(from: outputBuffer)
            }
            if status == .endOfStream || status == .error { break }
        }
    }

    private static func readerFailure() -> Error {
        NSError(domain: "AudioTranscoder", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "트랜스코드 실패"])
    }
}
