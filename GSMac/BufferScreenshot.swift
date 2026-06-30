import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import Observation

struct BufferScreenshot: Identifiable {
    let id        = UUID()
    let timestamp: Date
    let jpegData:  Data
}

enum ReplayError: LocalizedError {
    case noFootage
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFootage:              return "No buffered footage in the requested window."
        case .exportFailed(let msg):  return "Export failed: \(msg)"
        }
    }
}

@Observable
final class ReplayBufferManager {
    static let shared = ReplayBufferManager()

    private(set) var isRecording:     Bool  = false
    private(set) var bufferedSeconds: Int   = 0
    private(set) var screenshots:     [BufferScreenshot] = []

    // Config
    private var videoWidth:  Int  = 1920
    private var videoHeight: Int  = 1080
    private var hasAudio:    Bool = false
    private var maxBuffer:   Int  = 300

    // Segment writer state
    private var currentWriter:       AVAssetWriter?
    private var currentVideoInput:   AVAssetWriterInput?
    private var currentAudioInput:   AVAssetWriterInput?
    private var currentSegmentStart: Date = .now
    private var segmentSessionActive = false
    private var segmentTimer:        Timer?
    private let segmentLength:       TimeInterval = 10.0
    private var segments:            [(url: URL, start: Date, end: Date)] = []
    private let writerLock =         NSLock()

    // Screenshot buffer
    private var lastScreenshotTime = Date.distantPast
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let segmentDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GSMacReplayBuffer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Configure

    func configure(width: Int, height: Int, audio: Bool, maxBufferSeconds: Int) {
        videoWidth  = max(2, width)
        videoHeight = max(2, height)
        hasAudio    = audio
        maxBuffer   = maxBufferSeconds
    }

    // MARK: - Control

    @MainActor
    func start() {
        guard !isRecording else { return }
        clearAll()
        isRecording = true
        startNewSegment()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentLength, repeats: true) { [weak self] _ in
            self?.rotateSegment()
        }
        AppLogger.shared.log("Replay buffer started (\(maxBuffer)s window, \(Int(segmentLength))s segments, \(videoWidth)×\(videoHeight)).", level: .info)
    }

    @MainActor
    func stop() {
        guard isRecording else { return }
        isRecording = false
        segmentTimer?.invalidate()
        segmentTimer = nil
        writerLock.withLock {
            currentVideoInput?.markAsFinished()
            currentAudioInput?.markAsFinished()
            currentWriter?.finishWriting(completionHandler: {})
            currentWriter     = nil
            currentVideoInput = nil
            currentAudioInput = nil
        }
        AppLogger.shared.log("Replay buffer stopped. \(bufferedSeconds)s buffered, \(screenshots.count) screenshots.", level: .info)
    }

    // MARK: - Sample input

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        writerLock.withLock {
            guard isRecording,
                  let writer = currentWriter,
                  let input  = currentVideoInput,
                  input.isReadyForMoreMediaData else { return }

            if !segmentSessionActive {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                segmentSessionActive = true
            }

            input.append(sampleBuffer)
        }

        // Screenshot at 1fps — outside the lock, uses a copy of the buffer
        let now = Date()
        if now.timeIntervalSince(lastScreenshotTime) >= 1.0 {
            lastScreenshotTime = now
            captureScreenshot(from: sampleBuffer, at: now)
        }

        // Update buffered seconds counter
        if let first = segments.first?.start {
            let secs = min(maxBuffer, Int(Date().timeIntervalSince(first)))
            DispatchQueue.main.async { self.bufferedSeconds = secs }
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        writerLock.withLock {
            guard isRecording, hasAudio,
                  let input = currentAudioInput,
                  input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }
    }

    // MARK: - Screenshot access

    func latestScreenshot() -> CGImage? {
        screenshots.last.flatMap { cgImage(from: $0.jpegData) }
    }

    func screenshot(nearest date: Date) -> CGImage? {
        screenshots
            .min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
            .flatMap { cgImage(from: $0.jpegData) }
    }

    // MARK: - Save replay

    @MainActor
    func saveReplay(lastSeconds: Int) async throws -> URL {
        let cutoff   = Date().addingTimeInterval(-Double(lastSeconds))
        let relevant = segments.filter { $0.end > cutoff }

        guard !relevant.isEmpty else { throw ReplayError.noFootage }

        let composition = AVMutableComposition()
        let vTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let aTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero

        for seg in relevant {
            guard FileManager.default.fileExists(atPath: seg.url.path) else { continue }
            let asset = AVURLAsset(url: seg.url)
            let totalDuration = try await asset.load(.duration)

            let trimOffset = max(0.0, cutoff.timeIntervalSince(seg.start))
            let cmTrim     = CMTime(seconds: trimOffset, preferredTimescale: 600)
            let cmDur      = CMTimeSubtract(totalDuration, cmTrim)
            guard cmDur.seconds > 0 else { continue }
            let range = CMTimeRange(start: cmTrim, duration: cmDur)

            if let src = try await asset.loadTracks(withMediaType: .video).first {
                try vTrack?.insertTimeRange(range, of: src, at: cursor)
            }
            if let src = try await asset.loadTracks(withMediaType: .audio).first {
                try aTrack?.insertTimeRange(range, of: src, at: cursor)
            }
            cursor = CMTimeAdd(cursor, cmDur)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GSM_replay_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ReplayError.exportFailed("Could not create export session") }

        session.outputURL      = outputURL
        session.outputFileType = .mp4
        await session.export()

        if let error = session.error { throw error }

        AppLogger.shared.log("Replay saved: \(outputURL.lastPathComponent) (\(lastSeconds)s).", level: .info)
        return outputURL
    }

    // MARK: - Segment management

    private func startNewSegment() {
        let url = segmentDir.appendingPathComponent("seg_\(Int(Date().timeIntervalSince1970 * 1000)).mov")

        guard let writer = try? AVAssetWriter(url: url, fileType: .mov) else {
            AppLogger.shared.log("Failed to create segment writer.", level: .error)
            return
        }

        let vInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey:  AVVideoCodecType.hevc,
                AVVideoWidthKey:  videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000]
            ]
        )
        vInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vInput) { writer.add(vInput) }

        var aInput: AVAssetWriterInput? = nil
        if hasAudio {
            let ai = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey:         kAudioFormatMPEG4AAC,
                    AVSampleRateKey:       48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey:   128_000
                ]
            )
            ai.expectsMediaDataInRealTime = true
            if writer.canAdd(ai) { writer.add(ai); aInput = ai }
        }

        writer.startWriting()

        writerLock.withLock {
            currentWriter        = writer
            currentVideoInput    = vInput
            currentAudioInput    = aInput
            currentSegmentStart  = Date()
            segmentSessionActive = false
        }
    }

    private func rotateSegment() {
        var oldWriter:     AVAssetWriter?
        var oldVideoInput: AVAssetWriterInput?
        var oldAudioInput: AVAssetWriterInput?
        let segStart = currentSegmentStart

        writerLock.withLock {
            oldWriter     = currentWriter
            oldVideoInput = currentVideoInput
            oldAudioInput = currentAudioInput
            currentWriter     = nil
            currentVideoInput = nil
            currentAudioInput = nil
        }

        // Start fresh segment immediately so frames don't pile up
        startNewSegment()

        guard let writer = oldWriter else { return }
        let url = writer.outputURL

        oldVideoInput?.markAsFinished()
        oldAudioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.segments.append((url: url, start: segStart, end: Date()))
                self.pruneOldSegments()
            }
        }
    }

    private func pruneOldSegments() {
        let cutoff = Date().addingTimeInterval(-Double(maxBuffer))
        let old    = segments.filter { $0.end < cutoff }
        segments.removeAll { $0.end < cutoff }
        for seg in old { try? FileManager.default.removeItem(at: seg.url) }
    }

    // MARK: - Screenshot helpers

    private func captureScreenshot(from sampleBuffer: CMSampleBuffer, at date: Date) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else { return }

        let shot = BufferScreenshot(timestamp: date, jpegData: jpegData)
        DispatchQueue.main.async {
            self.screenshots.append(shot)
            if self.screenshots.count > self.maxBuffer { self.screenshots.removeFirst() }
        }
    }

    private func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private func clearAll() {
        segments     = []
        screenshots  = []
        bufferedSeconds = 0
        try? FileManager.default.removeItem(at: segmentDir)
        try? FileManager.default.createDirectory(at: segmentDir, withIntermediateDirectories: true)
    }
}
