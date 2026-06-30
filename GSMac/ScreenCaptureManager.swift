import Foundation
import ScreenCaptureKit
import CoreImage
import Observation

enum CaptureState: Equatable {
    case idle
    case permissionDenied
    case ready
    case capturing
    case failed(String)
}

enum CaptureSourceType: String, CaseIterable {
    case display = "Display"
    case window  = "Window (+ App Audio)"
}

struct CaptureDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let scDisplay: SCDisplay
    static func == (lhs: CaptureDisplay, rhs: CaptureDisplay) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct CaptureWindow: Identifiable, Hashable {
    let id: CGWindowID
    let scWindow: SCWindow
    var title:   String { scWindow.title ?? "Untitled Window" }
    var appName: String { scWindow.owningApplication?.applicationName ?? "Unknown App" }
    static func == (lhs: CaptureWindow, rhs: CaptureWindow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ThumbnailFrame: Identifiable, Equatable {
    let id        = UUID()
    let timestamp: Date
    let image:     CGImage

    static func == (lhs: ThumbnailFrame, rhs: ThumbnailFrame) -> Bool { lhs.id == rhs.id }
}

@Observable
final class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()

    private(set) var state:             CaptureState     = .idle
    private(set) var availableDisplays: [CaptureDisplay] = []
    private(set) var availableWindows:  [CaptureWindow]  = []
    private(set) var frameCount:        Int              = 0
    private(set) var audioFrameCount:   Int              = 0
    private(set) var latestFrame:       CGImage?         = nil
    private(set) var thumbnailFrames:   [ThumbnailFrame] = []

    var sourceType: CaptureSourceType = .display

    private var stream:          SCStream?
    private var selectedDisplay: SCDisplay?
    private var selectedWindow:  SCWindow?
    private var maxThumbnails =  300

    private let ciContext  = CIContext(options: [.useSoftwareRenderer: false])
    private let videoQueue = DispatchQueue(label: "com.gsmac.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.gsmac.audio", qos: .default)
    private var lastThumbnailTime: Date = .distantPast

    private override init() { super.init() }

    // MARK: - Permission

    func checkPermission() {
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run { self.state = .ready }
                AppLogger.shared.log("Screen Recording permission confirmed.", level: .info)
            } catch {
                await MainActor.run { self.state = .permissionDenied }
                AppLogger.shared.log("Screen Recording permission denied.", level: .warning)
            }
        }
    }

    // MARK: - Sources

    func refreshAvailableSources() {
        Task {
            do {
                let content  = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let displays = content.displays.map { CaptureDisplay(id: $0.displayID, scDisplay: $0) }
                let windows  = content.windows
                    .filter  { ($0.title ?? "").isEmpty == false }
                    .map     { CaptureWindow(id: $0.windowID, scWindow: $0) }
                await MainActor.run {
                    self.availableDisplays = displays
                    self.availableWindows  = windows
                    if self.selectedDisplay == nil { self.selectedDisplay = displays.first?.scDisplay }
                    if self.selectedWindow  == nil { self.selectedWindow  = windows.first?.scWindow  }
                    self.state = .ready
                }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
                AppLogger.shared.log("Failed to list capture sources: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func selectDisplay(_ display: CaptureDisplay) { selectedDisplay = display.scDisplay }
    func selectWindow (_ window:  CaptureWindow)  { selectedWindow  = window.scWindow   }

    // MARK: - Capture

    func startCapture(frameRate: Int, bufferSeconds: Int = 300) {
        maxThumbnails  = bufferSeconds
        thumbnailFrames = []
        latestFrame     = nil
        lastThumbnailTime = .distantPast

        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        let width:  Int
        let height: Int
        let audio:  Bool

        switch sourceType {
        case .display:
            guard let display = selectedDisplay else {
                state = .failed("No display selected")
                return
            }
            filter  = SCContentFilter(display: display, excludingWindows: [])
            width   = display.width
            height  = display.height
            audio   = false
            config.width  = width
            config.height = height
            config.capturesAudio = false

        case .window:
            guard let window = selectedWindow else {
                state = .failed("No window selected")
                return
            }
            filter  = SCContentFilter(desktopIndependentWindow: window)
            width   = max(2, Int(window.frame.width))
            height  = max(2, Int(window.frame.height))
            audio   = true
            config.width  = width
            config.height = height
            config.capturesAudio = true
            config.sampleRate    = 48000
            config.channelCount  = 2
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 5

        // Configure replay buffer
        ReplayBufferManager.shared.configure(
            width:            width,
            height:           height,
            audio:            audio,
            maxBufferSeconds: bufferSeconds
        )

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            if audio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            }
            Task {
                do {
                    try await stream.startCapture()
                    await MainActor.run { self.state = .capturing }
                    await ReplayBufferManager.shared.start()
                    AppLogger.shared.log("Capture started (\(self.sourceType.rawValue)) at \(frameRate) fps.", level: .info)
                } catch {
                    await MainActor.run { self.state = .failed(error.localizedDescription) }
                    AppLogger.shared.log("Failed to start capture: \(error.localizedDescription)", level: .error)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            AppLogger.shared.log("Stream configuration error: \(error.localizedDescription)", level: .error)
        }
    }

    func stopCapture() {
        Task {
            do {
                try await stream?.stopCapture()
                await ReplayBufferManager.shared.stop()
                await MainActor.run {
                    self.state          = .ready
                    self.frameCount     = 0
                    self.audioFrameCount = 0
                    self.latestFrame    = nil
                    self.thumbnailFrames = []
                }
                AppLogger.shared.log("Capture stopped.", level: .info)
            } catch {
                AppLogger.shared.log("Failed to stop capture: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Thumbnail helper

    private func downsample(_ source: CGImage, toWidth width: Int) -> CGImage? {
        let height = max(1, Int(Double(source.height) * Double(width) / Double(source.width)))
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
        AppLogger.shared.log("Stream stopped with error: \(error.localizedDescription)", level: .error)
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            // Forward to replay buffer (full-res HEVC + JPEG screenshots)
            ReplayBufferManager.shared.appendVideo(sampleBuffer)

            // Live preview frame + thumbnail for timeline UI
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            let now = Date()
            let needsThumb = now.timeIntervalSince(lastThumbnailTime) >= 1.0
            var thumb: CGImage? = nil
            if needsThumb {
                lastThumbnailTime = now
                thumb = downsample(cgImage, toWidth: 160)
            }

            let ts = now
            DispatchQueue.main.async {
                self.latestFrame  = cgImage
                self.frameCount  += 1
                if let thumb {
                    self.thumbnailFrames.append(ThumbnailFrame(timestamp: ts, image: thumb))
                    if self.thumbnailFrames.count > self.maxThumbnails {
                        self.thumbnailFrames.removeFirst()
                    }
                }
            }

        case .audio:
            ReplayBufferManager.shared.appendAudio(sampleBuffer)
            DispatchQueue.main.async { self.audioFrameCount += 1 }

        default:
            break
        }
    }
}
