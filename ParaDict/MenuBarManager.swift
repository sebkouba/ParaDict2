import SwiftUI
import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.paradict", category: "MenuBarManager")

class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool {
        didSet {
            UserDefaults.standard.set(isMenuBarOnly, forKey: "IsMenuBarOnly")
            logger.info("isMenuBarOnly changed to: \(self.isMenuBarOnly)")
            updateAppActivationPolicy()
        }
    }

    init() {
        // Default to NOT menu bar only - show main window on first launch
        self.isMenuBarOnly = UserDefaults.standard.object(forKey: "IsMenuBarOnly") != nil
            ? UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
            : false
        logger.info("MenuBarManager initialized - isMenuBarOnly: \(self.isMenuBarOnly)")
    }

    func toggleMenuBarOnly() {
        isMenuBarOnly.toggle()
    }

    func showMainWindow() {
        logger.info("showMainWindow called")
        isMenuBarOnly = false
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Find and show any window
        for window in NSApplication.shared.windows {
            logger.info("Found window: \(window.identifier?.rawValue ?? "nil") - isVisible: \(window.isVisible)")
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func updateAppActivationPolicy() {
        DispatchQueue.main.async {
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                logger.info("Setting activation policy to accessory")
                application.setActivationPolicy(.accessory)
            } else {
                logger.info("Setting activation policy to regular")
                application.setActivationPolicy(.regular)
                application.activate(ignoringOtherApps: true)
            }
        }
    }
}
