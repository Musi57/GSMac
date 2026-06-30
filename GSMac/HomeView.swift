import SwiftUI

struct HomeView: View {
    private var captureManager = ScreenCaptureManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                StatusBadge(label: "GSM",            status: "Ready",             isActive: true)
                StatusBadge(label: "Screen Capture", status: captureStatusText,   isActive: captureManager.state == .capturing)
                StatusBadge(label: "Anki",           status: "Not Connected",     isActive: false)
            }
            .padding(16)

            Divider()

            CapturePreviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var captureStatusText: String {
        switch captureManager.state {
        case .idle:             return "Idle"
        case .permissionDenied: return "Permission Denied"
        case .ready:            return "Ready"
        case .capturing:        return "Capturing"
        case .failed:           return "Failed"
        }
    }
}
