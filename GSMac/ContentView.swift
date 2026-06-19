import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "Home"
    case ocr = "OCR"
    case textProcessing = "Text Processing"
    case stats = "Stats"
    case gameAutomation = "Game Automation"
    case settings = "Settings"
    case logs = "Logs"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home

    @AppStorage("obsHost") private var obsHost = "127.0.0.1"
    @AppStorage("obsPort") private var obsPort = 7274
    @AppStorage("obsAuthEnabled") private var obsAuthEnabled = false
    @AppStorage("obsPassword") private var obsPassword = ""

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selectedTab: $selectedTab)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            AppLogger.shared.log("Application launched", level: .info)
            OBSConnectionManager.shared.connect(
                host: obsHost,
                port: obsPort,
                password: obsAuthEnabled ? obsPassword : nil
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .logs:
            LogsView()
        case.settings:
            SettingsView()
        default:
            PlaceholderView(title: selectedTab.rawValue)
        }
    }
}

struct TabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.spring(duration: 0.3), value: selectedTab)
    }

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let label = Text(tab.rawValue)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())

        Button {
            selectedTab = tab
        } label: {
            if selectedTab == tab {
                label
                    .foregroundStyle(.white)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.5)).interactive(), in: Capsule())
            } else {
                label
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
