import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("captureFrameRate") private var captureFrameRate = 15
    @AppStorage("replayBufferEnabled") private var replayBufferEnabled = true
    @AppStorage("replayBufferSeconds") private var replayBufferSeconds = 300

    private var captureManager = ScreenCaptureManager.shared
    @State private var selectedDisplayID: CGDirectDisplayID?
    @State private var selectedWindowID: CGWindowID?

    private let fieldWidth: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                captureSourceCard
                outputCard
                replayBufferCard
                captureControlCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onAppear {
            captureManager.refreshAvailableSources()
        }
    }

    private var captureSourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Capture Source")
                .font(.headline)
                .padding(.bottom, 8)

            cardBackground {
                VStack(spacing: 0) {
                    settingsRow(label: "Capture Type") {
                        Picker("", selection: Binding(
                            get: { captureManager.sourceType },
                            set: { captureManager.sourceType = $0 }
                        )) {
                            ForEach(CaptureSourceType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: fieldWidth)
                    }

                    Divider().padding(.leading, 14)

                    if captureManager.sourceType == .display {
                        settingsRow(label: "Display") {
                            Picker("", selection: $selectedDisplayID) {
                                ForEach(captureManager.availableDisplays) { display in
                                    Text("Display \(display.id)").tag(Optional(display.id))
                                }
                            }
                            .labelsHidden()
                            .frame(width: fieldWidth)
                            .onChange(of: selectedDisplayID) { _, newValue in
                                if let newValue, let display = captureManager.availableDisplays.first(where: { $0.id == newValue }) {
                                    captureManager.selectDisplay(display)
                                }
                            }
                        }
                    } else {
                        settingsRow(label: "Window") {
                            Picker("", selection: $selectedWindowID) {
                                ForEach(captureManager.availableWindows) { window in
                                    Text("\(window.appName) — \(window.title)").tag(Optional(window.id))
                                }
                            }
                            .labelsHidden()
                            .frame(width: fieldWidth)
                            .onChange(of: selectedWindowID) { _, newValue in
                                if let newValue, let window = captureManager.availableWindows.first(where: { $0.id == newValue }) {
                                    captureManager.selectWindow(window)
                                }
                            }
                        }
                    }

                    Divider().padding(.leading, 14)
                    settingsRow(label: "") {
                        Button("Refresh Sources") {
                            captureManager.refreshAvailableSources()
                        }
                    }
                }
            }

            Text("Display captures your whole screen. Window mode captures a single window and that application's audio — useful for grabbing just the game's sound, similar to OBS's Window + Application Audio Capture.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Output")
                .font(.headline)
                .padding(.bottom, 8)

            cardBackground {
                settingsRow(label: "Frame Rate") {
                    Picker("", selection: $captureFrameRate) {
                        Text("60 fps").tag(60)
                        Text("30 fps").tag(30)
                        Text(defaultFrameRateLabel).tag(15)
                    }
                    .labelsHidden()
                    .frame(width: fieldWidth)
                }
            }
        }
    }

    private var replayBufferCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Replay Buffer")
                .font(.headline)
                .padding(.bottom, 8)

            cardBackground {
                VStack(spacing: 0) {
                    settingsRow(label: "Enable Replay Buffer") {
                        Toggle("", isOn: $replayBufferEnabled)
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 14)
                    settingsRow(label: "Max Replay Time") {
                        Stepper(value: $replayBufferSeconds, in: 30...600, step: 30) {
                            Text("\(replayBufferSeconds)s")
                        }
                    }
                }
            }

            Text("macOS has no built-in rolling buffer like OBS — this will drive a custom segmented-recording system we build separately. Not active yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private var captureControlCard: some View {
        cardBackground {
            VStack(spacing: 0) {
                settingsRow(label: "") {
                    HStack(spacing: 8) {
                        Button("Start Capture") {
                            captureManager.startCapture(frameRate: captureFrameRate)
                        }
                        Button("Stop Capture") {
                            captureManager.stopCapture()
                        }
                    }
                }
                Divider().padding(.leading, 14)
                settingsRow(label: "Status") {
                    statusView
                }
                if captureManager.state == .capturing {
                    Divider().padding(.leading, 14)
                    settingsRow(label: "Frames") {
                        Text("Video: \(captureManager.frameCount)   Audio: \(captureManager.audioFrameCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            if !label.isEmpty { Text(label) }
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func cardBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var defaultFrameRateLabel: AttributedString {
        var label = AttributedString("15 fps   ")
        var suffix = AttributedString("Default")
        suffix.foregroundColor = .secondary
        suffix.font = .caption
        label.append(suffix)
        return label
    }

    @ViewBuilder
    private var statusView: some View {
        switch captureManager.state {
        case .idle:             Text("Idle").foregroundStyle(.secondary)
        case .permissionDenied: Text("Permission Denied").foregroundStyle(.red)
        case .ready:            Text("Ready").foregroundStyle(.secondary)
        case .capturing:        Text("Capturing").foregroundStyle(.green)
        case .failed:           Text("Capture Failed").foregroundStyle(.red)
        }
    }
}

#Preview {
    SettingsView()
}
