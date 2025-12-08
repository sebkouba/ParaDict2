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
            updateAppActivationPolicy()
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

    func showMainWindow() {
        logger.notice("showMainWindow called")
        isMenuBarOnly = false
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Find the main window (not menu bar popover windows)
        if let mainWindow = NSApplication.shared.windows.first(where: { window in
            // Skip menu bar extra windows and other utility windows
            window.level == .normal && window.canBecomeKey
        }) {
            logger.notice("Bringing main window to front: \(mainWindow.identifier?.rawValue ?? "nil")")
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
        } else {
            // Fallback: try to show any available window
            for window in NSApplication.shared.windows {
                logger.notice("Found window: \(window.identifier?.rawValue ?? "nil") - isVisible: \(window.isVisible), level: \(window.level.rawValue)")
                if window.canBecomeKey {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    break
                }
            }
        }
    }

    private func updateAppActivationPolicy() {
        DispatchQueue.main.async {
            let application = NSApplication.shared
            if self.isMenuBarOnly {
                logger.notice("Setting activation policy to accessory")
                application.setActivationPolicy(.accessory)
            } else {
                logger.notice("Setting activation policy to regular")
                application.setActivationPolicy(.regular)
                application.activate(ignoringOtherApps: true)
            }
        }
    }
}
