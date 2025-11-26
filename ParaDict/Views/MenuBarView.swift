import SwiftUI
import KeyboardShortcuts
import os

private let logger = Logger(subsystem: "com.paradict", category: "MenuBarView")

struct MenuBarView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var dictationManager: DictationManager
    @EnvironmentObject var menuBarManager: MenuBarManager

    var body: some View {
        VStack {
            Button(statusText) {
                // Status button - no action, just shows state
            }
            .disabled(true)

            Divider()

            Button("Open ParaDict") {
                logger.notice("Opening main window")
                menuBarManager.showMainWindow()
            }

            Button("Open Config File") {
                logger.notice("Opening config file")
                NSWorkspace.shared.open(URL(fileURLWithPath: configManager.configFilePath))
            }

            Divider()

            Button("Quit ParaDict") {
                logger.notice("Quit requested")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var statusText: String {
        switch dictationManager.state {
        case .idle:
            return "Status: Ready"
        case .recording:
            return "Status: Recording..."
        case .transcribing:
            return "Status: Transcribing..."
        case .enhancing:
            return "Status: Enhancing..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
