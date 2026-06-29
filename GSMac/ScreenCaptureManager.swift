import Foundation
import ScreenCaptureKit
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
    case window = "Window (+ App Audio)"
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

    var title: String { scWindow.title ?? "Untitled Window" }
    var appName: String { scWindow.owningApplication?.applicationName ?? "Unknown App" }

    static func == (lhs: CaptureWindow, rhs: CaptureWindow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Observable
final class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()

    private(set) var state: CaptureState = .idle
    private(set) var availableDisplays: [CaptureDisplay] = []
    private(set) var availableWindows: [CaptureWindow] = []
    private(set) var frameCount: Int = 0
    private(set) var audioFrameCount: Int = 0

    var sourceType: CaptureSourceType = .display

    private var stream: SCStream?
    private var selectedDisplay: SCDisplay?
    private var selectedWindow: SCWindow?

    private override init() {
        super.init()
    }

    func checkPermission() {
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run { self.state = .ready }
                AppLogger.shared.log("Screen Recording permission confirmed.", level: .info)
            } catch {
                await MainActor.run { self.state = .permissionDenied }
                AppLogger.shared.log("Screen Recording permission not granted: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    func refreshAvailableSources() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let displays = content.displays.map { CaptureDisplay(id: $0.displayID, scDisplay: $0) }
                let windows = content.windows
                    .filter { ($0.title ?? "").isEmpty == false }
                    .map { CaptureWindow(id: $0.windowID, scWindow: $0) }

                await MainActor.run {
                    self.availableDisplays = displays
                    self.availableWindows = windows
                    if self.selectedDisplay == nil { self.selectedDisplay = displays.first?.scDisplay }
                    if self.selectedWindow == nil { self.selectedWindow = windows.first?.scWindow }
                    self.state = .ready
                }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
                AppLogger.shared.log("Failed to list capture sources: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func selectDisplay(_ display: CaptureDisplay) {
        selectedDisplay = display.scDisplay
    }

    func selectWindow(_ window: CaptureWindow) {
        selectedWindow = window.scWindow
    }

    func startCapture(frameRate: Int) {
        let filter: SCContentFilter
        let config = SCStreamConfiguration()

        switch sourceType {
        case .display:
            guard let display = selectedDisplay else {
                AppLogger.shared.log("No display selected for capture.", level: .error)
                state = .failed("No display selected")
                return
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            config.width = display.width
            config.height = display.height
            config.capturesAudio = false

        case .window:
            guard let window = selectedWindow else {
                AppLogger.shared.log("No window selected for capture.", level: .error)
                state = .failed("No window selected")
                return
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            if config.capturesAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
            }
            Task {
                do {
                    try await stream.startCapture()
                    await MainActor.run {
                        self.state = .capturing
                        self.frameCount = 0
                        self.audioFrameCount = 0
                    }
                    AppLogger.shared.log("Capture started (\(self.sourceType.rawValue)) at \(frameRate) fps.", level: .info)
                } catch {
                    await MainActor.run { self.state = .failed(error.localizedDescription) }
                    AppLogger.shared.log("Failed to start capture: \(error.localizedDescription)", level: .error)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            AppLogger.shared.log("Failed to add stream output: \(error.localizedDescription)", level: .error)
        }
    }

    func stopCapture() {
        Task {
            do {
                try await stream?.stopCapture()
                await MainActor.run {
                    self.state = .ready
                    self.frameCount = 0
                    self.audioFrameCount = 0
                }
                AppLogger.shared.log("Capture stopped.", level: .info)
            } catch {
                AppLogger.shared.log("Failed to stop capture: \(error.localizedDescription)", level: .error)
            }
        }
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
        AppLogger.shared.log("Stream stopped with error: \(error.localizedDescription)", level: .error)
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            DispatchQueue.main.async { self.frameCount += 1 }
        case .audio:
            DispatchQueue.main.async { self.audioFrameCount += 1 }
        default:
            break
        }
    }
}
