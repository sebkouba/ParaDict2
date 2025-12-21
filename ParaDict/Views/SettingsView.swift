import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PermissionsView()
                .tabItem {
                    Label("Permissions", systemImage: "shield.lefthalf.filled")
                }
                .tag(0)

            AudioInputView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
                .tag(1)

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(2)

            LLMSettingsView()
                .tabItem {
                    Label("LLM", systemImage: "brain.head.profile")
                }
                .tag(3)

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(4)

            DirectoryWatcherView()
                .tabItem {
                    Label("Watcher", systemImage: "folder.badge.gearshape")
                }
                .tag(5)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

#Preview {
    SettingsView()
}
