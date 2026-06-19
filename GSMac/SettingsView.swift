import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("obsHost") private var obsHost = "127.0.0.1"
    @AppStorage("obsPort") private var obsPort = 7274
    @AppStorage("obsAuthEnabled") private var obsAuthEnabled = false
    @AppStorage("obsPassword") private var obsPassword = ""
    @AppStorage("replayBufferEnabled") private var replayBufferEnabled = true
    @AppStorage("replayBufferSeconds") private var replayBufferSeconds = 300
    @AppStorage("obsFrameRate") private var obsFrameRate = 30

    private var obsManager = OBSConnectionManager.shared

    private let fieldWidth: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                obsConnectionCard
                replayBufferCard
                outputCard
                testConnectionCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    // MARK: - OBS Connection

    private var obsConnectionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OBS Connection")
                .font(.headline)
                .padding(.bottom, 8)

            cardBackground {
                VStack(spacing: 0) {
                    settingsRow(label: "Host") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("127.0.0.1", text: $obsHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: fieldWidth)
                            Text("Default: 127.0.0.1")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider().padding(.leading, 14)
                    settingsRow(label: "Port") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("7274", value: $obsPort, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: fieldWidth)
                            Text("Default: 7274")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider().padding(.leading, 14)
                    settingsRow(label: "Enable Authentication") {
                        Toggle("", isOn: $obsAuthEnabled)
                            .labelsHidden()
                    }
                    if obsAuthEnabled {
                        Divider().padding(.leading, 14)
                        settingsRow(label: "Password") {
                            SecureField("Password", text: $obsPassword)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: fieldWidth)
                        }
                    }
                }
            }

            Text("Make sure WebSocket Server is enabled in OBS under Tools → WebSocket Server Settings, with a matching port.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    // MARK: - Replay Buffer

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

            Text("300 seconds is recommended for flexibility when mining older lines.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    // MARK: - Output

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Output")
                .font(.headline)
                .padding(.bottom, 8)

            cardBackground {
                settingsRow(label: "Frame Rate") {
                    Picker("", selection: $obsFrameRate) {
                        Text("60 fps").tag(60)
                        Text(defaultFrameRateLabel).tag(30)
                        Text("15 fps").tag(15)
                    }
                    .labelsHidden()
                    .frame(width: fieldWidth)
                }
            }
        }
    }

    // MARK: - Test Connection

    private var testConnectionCard: some View {
        cardBackground {
            VStack(spacing: 0) {
                settingsRow(label: "") {
                    Button("Test Connection") {
                        OBSConnectionManager.shared.connect(
                            host: obsHost,
                            port: obsPort,
                            password: obsAuthEnabled ? obsPassword : nil
                        )
                    }
                }
                Divider().padding(.leading, 14)
                settingsRow(label: "Status") {
                    statusView
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            if !label.isEmpty {
                Text(label)
            }
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
        var label = AttributedString("30 fps   ")
        var suffix = AttributedString("Default")
        suffix.foregroundColor = .secondary
        suffix.font = .caption
        label.append(suffix)
        return label
    }

    @ViewBuilder
    private var statusView: some View {
        switch obsManager.state {
        case .disconnected:
            Text("Not Connected").foregroundStyle(.secondary)
        case .connecting:
            Text("Connecting…").foregroundStyle(.yellow)
        case .connected:
            Text("Connected").foregroundStyle(.green)
        case .failed:
            Text("Connection Failed").foregroundStyle(.red)
        }
    }
}

#Preview {
    SettingsView()
}
