import SwiftUI

struct CapturePreviewView: View {
    private var captureManager = ScreenCaptureManager.shared
    private var replayBuffer   = ReplayBufferManager.shared

    @State private var selectedFrameID: UUID?     = nil
    @State private var isSavingReplay:  Bool      = false
    @State private var saveResult:      String?   = nil
    @State private var savedURL:        URL?       = nil

    private var isLive: Bool { selectedFrameID == nil }

    private var displayedImage: CGImage? {
        if let id = selectedFrameID,
           let frame = captureManager.thumbnailFrames.first(where: { $0.id == id }) {
            // Show full-res screenshot closest to this timestamp from replay buffer
            return replayBuffer.screenshot(nearest: frame.timestamp)
                ?? captureManager.latestFrame
        }
        return captureManager.latestFrame
    }

    private var selectedTimestamp: Date? {
        guard let id = selectedFrameID else { return nil }
        return captureManager.thumbnailFrames.first(where: { $0.id == id })?.timestamp
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            Divider()
            timelineArea
        }
        .onChange(of: captureManager.thumbnailFrames) { _, frames in
            if let id = selectedFrameID, !frames.contains(where: { $0.id == id }) {
                selectedFrameID = nil
            }
        }
    }

    // MARK: - Preview

    private var previewArea: some View {
        ZStack(alignment: .topTrailing) {
            Color.black

            if let image = displayedImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: captureManager.state == .capturing ? "clock" : "display")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(captureManager.state == .capturing
                         ? "Waiting for first frame…"
                         : "Start capture in Settings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // Live / timestamp badge (top-left)
            Group {
                if let ts = selectedTimestamp {
                    Text(ts.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, design: .monospaced))
                        .overlayBadge()
                } else if captureManager.state == .capturing {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 10, weight: .bold))
                    }
                    .overlayBadge()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)

            // Action buttons (top-right)
            if captureManager.state == .capturing {
                HStack(spacing: 6) {
                    Button {
                        saveScreenshot()
                    } label: {
                        Label("Screenshot", systemImage: "camera")
                            .font(.system(size: 11))
                    }
                    .overlayBadge()

                    Button {
                        saveReplay()
                    } label: {
                        if isSavingReplay {
                            ProgressView().controlSize(.mini)
                                .frame(width: 60)
                        } else {
                            Label("Save Replay", systemImage: "record.circle")
                                .font(.system(size: 11))
                        }
                    }
                    .overlayBadge()
                    .disabled(isSavingReplay || replayBuffer.bufferedSeconds < 5)
                }
                .padding(10)
            }

            // Save result toast (bottom)
            if let result = saveResult {
                Text(result)
                    .font(.caption)
                    .overlayBadge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Timeline

    private var timelineArea: some View {
        VStack(spacing: 0) {
            if captureManager.thumbnailFrames.isEmpty {
                HStack {
                    Text(captureManager.state == .capturing
                         ? "Building buffer — one thumbnail per second…"
                         : "No buffer data. Start capture to begin recording.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(height: 80)
                .padding(.horizontal, 12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 3) {
                            ForEach(captureManager.thumbnailFrames) { frame in
                                thumbnailCell(frame)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 104)
                    .onChange(of: captureManager.thumbnailFrames.count) { _, _ in
                        guard isLive else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(captureManager.thumbnailFrames.last?.id, anchor: .trailing)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(captureManager.thumbnailFrames.last?.id, anchor: .trailing)
                    }
                }
            }

            Divider()

            // Status strip
            HStack(spacing: 12) {
                bufferHealthView

                Spacer()

                if replayBuffer.isRecording {
                    Text("\(replayBuffer.screenshots.count) screenshots in buffer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let url = savedURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }

                if !isLive {
                    Button("↩ Return to Live") {
                        withAnimation { selectedFrameID = nil }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var bufferHealthView: some View {
        HStack(spacing: 6) {
            let buffered = replayBuffer.bufferedSeconds
            let max      = ReplayBufferManager.shared.bufferedSeconds == 0
                         ? 1
                         : max(1, UserDefaults.standard.integer(forKey: "replayBufferSeconds") == 0
                            ? 300
                            : UserDefaults.standard.integer(forKey: "replayBufferSeconds"))
            let fraction = min(1.0, Double(buffered) / Double(max))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(buffered > 10 ? Color.green : Color.orange)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 80, height: 4)

            Text("\(replayBuffer.bufferedSeconds)s buffered")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Thumbnail cell

    private func thumbnailCell(_ frame: ThumbnailFrame) -> some View {
        let isSelected = selectedFrameID == frame.id
        return VStack(spacing: 3) {
            Image(decorative: frame.image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 45)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(frame.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                selectedFrameID = isSelected ? nil : frame.id
            }
        }
        .id(frame.id)
    }

    // MARK: - Actions

    private func saveScreenshot() {
        let image: CGImage?
        if let ts = selectedTimestamp {
            image = replayBuffer.screenshot(nearest: ts)
        } else {
            image = replayBuffer.latestScreenshot() ?? captureManager.latestFrame
        }

        guard let image else {
            showResult("No frame available")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GSM_screenshot_\(Int(Date().timeIntervalSince1970)).jpg")

        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        CGImageDestinationFinalize(dest)

        savedURL = url
        showResult("Screenshot saved")
        AppLogger.shared.log("Screenshot saved: \(url.lastPathComponent)", level: .info)
    }

    private func saveReplay() {
        isSavingReplay = true
        let seconds = UserDefaults.standard.integer(forKey: "replayBufferSeconds")
        let secs = seconds > 0 ? seconds : 300

        Task {
            do {
                let url = try await ReplayBufferManager.shared.saveReplay(lastSeconds: secs)
                await MainActor.run {
                    self.savedURL      = url
                    self.isSavingReplay = false
                    self.showResult("Replay saved (\(secs)s)")
                }
            } catch {
                await MainActor.run {
                    self.isSavingReplay = false
                    self.showResult("Save failed: \(error.localizedDescription)")
                    AppLogger.shared.log("Save replay failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func showResult(_ message: String) {
        withAnimation { saveResult = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { self.saveResult = nil }
        }
    }
}

// MARK: - Badge modifier

private struct OverlayBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private extension View {
    func overlayBadge() -> some View { modifier(OverlayBadgeModifier()) }
}
