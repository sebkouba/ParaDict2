import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var dictationCoordinator: DictationCoordinator
    @EnvironmentObject var menuBarManager: MenuBarManager

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatSettingsView()
                .environmentObject(configManager)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            PermissionsView()
                .tabItem {
                    Label("Permissions", systemImage: "shield.lefthalf.filled")
                }
                .tag(1)

            AudioInputView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
                .tag(2)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ConfigManager.shared)
        .environmentObject(DictationCoordinator.shared)
        .environmentObject(MenuBarManager())
}
