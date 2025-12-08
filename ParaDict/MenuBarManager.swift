import SwiftUI
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.paradict", category: "MenuBarManager")

class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()

    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            logger.notice("isMenuBarOnly changed to: \(self.isMenuBarOnly)")
            applyActivationPolicy()
        }
    }

    private init() {
        // Default to NOT menu bar only - show main window on first launch
        self.isMenuBarOnly = UserDefaults.standard.object(forKey: "IsMenuBarOnly") != nil
            ? UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
            : false
        logger.notice("MenuBarManager initialized - isMenuBarOnly: \(self.isMenuBarOnly)")
    }

    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }

    /// Shows the main window, creating it if necessary.
    func showMainWindow() {
        logger.notice("showMainWindow called")
        isMenuBarOnly = false
        applyActivationPolicy()

        // Try to show existing window via WindowManager
        if WindowManager.shared.showMainWindow() != nil {
            logger.notice("Showed existing main window")
            return
        }

        // No window exists yet - we need to trigger SwiftUI to create one
        // This simulates what happens when user clicks the dock icon
        logger.notice("No existing window, triggering window creation")

        // Activate the app - this combined with returning true from
        // applicationShouldHandleReopen will trigger SwiftUI to create a window
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Post a reopen notification to trigger window creation
        // This mimics clicking the dock icon
        DispatchQueue.main.async {
            let notification = Notification(name: NSApplication.didBecomeActiveNotification)
            NotificationCenter.default.post(notification)

            // After a brief delay, try to show the window again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = WindowManager.shared.showMainWindow() {
                    logger.notice("Window created and shown: \(window.identifier?.rawValue ?? "nil")")
                } else {
                    // Last resort: try to open a new window via the standard mechanism
                    logger.notice("Attempting NSApp.sendAction to create window")
                    NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
                }
            }
        }
    }

    /// Applies the current activation policy (regular or accessory).
    func applyActivationPolicy() {
        let apply = {
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                logger.notice("Setting activation policy to accessory")
                application.setActivationPolicy(.accessory)
                WindowManager.shared.hideMainWindow()
            } else {
                logger.notice("Setting activation policy to regular")
                application.setActivationPolicy(.regular)
            }
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}
