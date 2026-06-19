import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Status")
                .font(.headline)

            HStack(spacing: 12) {
                StatusBadge(label: "GSM", status: "Ready", isActive: true)
                StatusBadge(label: "WebSocket", status: "Disconnected", isActive: false)
                StatusBadge(label: "OBS", status: "Not Connected", isActive: false)
                StatusBadge(label: "Anki", status: "Not Connected", isActive: false)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
