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

struct CaptureDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let scDisplay: SCDisplay

    static func == (lhs: CaptureDisplay, rhs: CaptureDisplay) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
final class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()

    private(set) var state: CaptureState = .idle
    private(set) var availableDisplays: [CaptureDisplay] = []
    private(set) var frameCount: Int = 0

    private var stream: SCStream?
    private var selectedDisplay: SCDisplay?

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
                let content = try await SCShareableContent.current
                let displays = content.displays.map { CaptureDisplay(id: $0.displayID, scDisplay: $0) }
                await MainActor.run {
                    self.availableDisplays = displays
                    if self.selectedDisplay == nil {
                        self.selectedDisplay = displays.first?.scDisplay
                    }
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

    func startCapture(frameRate: Int) {
        guard let display = selectedDisplay else {
            AppLogger.shared.log("No display selected for capture.", level: .error)
            state = .failed("No display selected")
            return
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            Task {
                do {
                    try await stream.startCapture()
                    await MainActor.run { self.state = .capturing }
                    AppLogger.shared.log("Screen capture started at \(frameRate) fps.", level: .info)
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
                }
                AppLogger.shared.log("Screen capture stopped.", level: .info)
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
        guard type == .screen else { return }
        DispatchQueue.main.async { self.frameCount += 1 }
    }
}
