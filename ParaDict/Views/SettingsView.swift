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

            TranscriptionSettingsView()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
                .tag(2)

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(3)

            LLMSettingsView()
                .tabItem {
                    Label("LLM", systemImage: "brain.head.profile")
                }
                .tag(4)

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(5)

            DirectoryWatcherView()
                .tabItem {
                    Label("Watcher", systemImage: "folder.badge.gearshape")
                }
                .tag(6)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

#Preview {
    SettingsView()
}
