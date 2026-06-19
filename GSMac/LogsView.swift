import SwiftUI

struct LogsView: View {
    private var logger = AppLogger.shared
    @State private var filterLevel: LogLevel? = nil

    private var filteredEntries: [LogEntry] {
        guard let filterLevel else { return logger.entries }
        return logger.entries.filter { $0.level == filterLevel }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("Filter", selection: $filterLevel) {
                Text("All").tag(LogLevel?.none)
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(Optional(level))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            Button("Clear") { logger.clear() }
        }
        .padding(12)
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredEntries) { entry in
                    logRow(entry)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)

            Text(entry.level.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color(for: entry.level))
                .frame(width: 60, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:   return .gray
        case .info:    return .blue
        case .warning: return .yellow
        case .error:   return .red
        }
    }
}
