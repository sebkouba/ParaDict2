import AppKit
import os

private let logger = Logger(
    subsystem: "com.paradict",
    category: "ApplicationInstanceService"
)

/// Prevents independently launched app bundles from registering duplicate
/// global shortcuts and processing the same dictation more than once.
@MainActor
final class ApplicationInstanceService {
    static let shared = ApplicationInstanceService()

    private init() {}

    /// Activates an already-running copy and returns true when this launch
    /// should terminate before initializing any app services.
    func shouldTerminateCurrentInstance() -> Bool {
        // Hosted unit tests launch a ParaDict process while the installed app
        // may be running; that process must stay alive to load the test bundle.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            logger.error("Cannot check for another instance without a bundle identifier")
            return false
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        let processIdentifiers = runningApplications.map(\.processIdentifier)

        guard let existingProcessIdentifier = Self.otherProcessIdentifier(
            currentProcessIdentifier: currentProcessIdentifier,
            runningProcessIdentifiers: processIdentifiers
        ), let existingApplication = runningApplications.first(where: {
            $0.processIdentifier == existingProcessIdentifier
        }) else {
            return false
        }

        logger.warning(
            "Another ParaDict instance is already running (PID: \(existingProcessIdentifier)); terminating this launch (PID: \(currentProcessIdentifier))"
        )
        existingApplication.activate(options: [.activateAllWindows])
        return true
    }

    nonisolated static func otherProcessIdentifier(
        currentProcessIdentifier: pid_t,
        runningProcessIdentifiers: [pid_t]
    ) -> pid_t? {
        runningProcessIdentifiers.first { $0 != currentProcessIdentifier }
    }
}
