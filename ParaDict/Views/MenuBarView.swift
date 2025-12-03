import SwiftUI
import KeyboardShortcuts
import os

private let logger = Logger(subsystem: "com.paradict", category: "MenuBarView")

struct MenuBarView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var dictationCoordinator: DictationCoordinator
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

            if dictationCoordinator.lastTranscription != nil || dictationCoordinator.lastEnhancement != nil {
                if let transcription = dictationCoordinator.lastTranscription {
                    Button("Copy Last Transcription") {
                        logger.notice("Copying last transcription to clipboard")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcription, forType: .string)
                    }
                }

                if let enhancement = dictationCoordinator.lastEnhancement {
                    Button("Copy Last Enhancement") {
                        logger.notice("Copying last enhancement to clipboard")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(enhancement, forType: .string)
                    }
                }

                Divider()
            }

            Button("Quit ParaDict") {
                logger.notice("Quit requested")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var statusText: String {
        switch dictationCoordinator.state {
        case .idle:
            return "Status: Ready"
        case .recording:
            return "Status: Recording..."
        case .transcribing:
            return "Status: Transcribing..."
        case .enhancing:
            return "Status: Enhancing..."
        case .pasting:
            return "Status: Pasting..."
        case .executingCommand:
            return "Status: Executing..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
