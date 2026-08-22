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

    private static func readerFailure() -> Error {
        NSError(domain: "AudioTranscoder", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "트랜스코드 실패"])
    }
}
