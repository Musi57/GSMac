import SwiftUI

struct SettingsView: View {
    @AppStorage("obsHost") private var obsHost = "127.0.0.1"
    @AppStorage("obsPort") private var obsPort = 7274
    @AppStorage("obsAuthEnabled") private var obsAuthEnabled = false
    @AppStorage("obsPassword") private var obsPassword = ""
    @AppStorage("replayBufferEnabled") private var replayBufferEnabled = true
    @AppStorage("replayBufferSeconds") private var replayBufferSeconds = 300
    @AppStorage("obsFrameRate") private var obsFrameRate = 30

    private var obsManager = OBSConnectionManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Host")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("127.0.0.1", text: $obsHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Text("Default: 127.0.0.1")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Port")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("7274", value: $obsPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("Default: 7274")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Enable Authentication", isOn: $obsAuthEnabled)
                if obsAuthEnabled {
                    LabeledContent("Password") {
                        SecureField("Password", text: $obsPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                    }
                }
            } header: {
                Text("OBS Connection")
            } footer: {
                Text("Make sure WebSocket Server is enabled in OBS under Tools → WebSocket Server Settings, with a matching port. Leave Authentication off for now — it's the more reliable path on macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Replay Buffer", isOn: $replayBufferEnabled)
                Stepper(value: $replayBufferSeconds, in: 30...600, step: 30) {
                    LabeledContent("Max Replay Time", value: "\(replayBufferSeconds)s")
                }
            } header: {
                Text("Replay Buffer")
            } footer: {
                Text("300 seconds is recommended for flexibility when mining older lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Frame Rate", selection: $obsFrameRate) {
                    Text("60 fps").tag(60)
                    Text(defaultFrameRateLabel).tag(30)
                    Text("15 fps").tag(15)
                }
            } header: {
                Text("Output")
            }

            Section {
                Button("Test Connection") {
                    OBSConnectionManager.shared.connect(
                        host: obsHost,
                        port: obsPort,
                        password: obsAuthEnabled ? obsPassword : nil
                    )
                }
                LabeledContent("Status") {
                    statusView
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, alignment: .center)
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
