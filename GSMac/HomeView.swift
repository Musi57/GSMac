import SwiftUI

struct HomeView: View {
    private var obsManager = OBSConnectionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Status")
                .font(.headline)

            HStack(spacing: 12) {
                StatusBadge(label: "GSM", status: "Ready", isActive: true)
                StatusBadge(label: "WebSocket", status: "Disconnected", isActive: false)
                StatusBadge(label: "OBS", status: obsStatusText, isActive: obsManager.state == .connected)
                StatusBadge(label: "Anki", status: "Not Connected", isActive: false)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var obsStatusText: String {
        switch obsManager.state {
        case .disconnected: return "Not Connected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .failed:       return "Connection Failed"
        }
    }
}
