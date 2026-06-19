import SwiftUI

struct StatusBadge: View {
    let label: String
    let status: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? .green : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
