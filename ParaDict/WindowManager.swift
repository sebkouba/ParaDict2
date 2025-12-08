import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.paradict", category: "WindowManager")

/// Manages the main application window lifecycle.
/// Windows register themselves via WindowAccessor and can be reliably retrieved by identifier.
class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("com.paradict.mainWindow")
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName("ParaDictMainWindowFrame")

    private weak var mainWindow: NSWindow?
    private var didApplyInitialPlacement = false

    private override init() {
        super.init()
    }

    /// Configures a window as the main application window.
    /// Called from WindowAccessor when the SwiftUI view's window becomes available.
    func configureWindow(_ window: NSWindow) {
        // If we already have a main window with this identifier, just bring it to front
        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier == Self.mainWindowIdentifier && $0 != window
        }) {
            logger.notice("Main window already exists, closing duplicate and showing existing")
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        logger.notice("Configuring main window")

        // Configure window style
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = "ParaDict"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)

        applyInitialPlacementIfNeeded(to: window)
        registerMainWindow(window)

        window.orderFrontRegardless()
    }

    /// Registers a window as the main window and sets up delegation.
    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
        logger.notice("Registered main window: \(window.identifier?.rawValue ?? "nil")")
    }

    /// Shows the main window and brings it to the current Space.
    /// Returns the window if successful, nil if no window exists.
    @discardableResult
    func showMainWindow() -> NSWindow? {
        guard let window = resolveMainWindow() else {
            logger.notice("No main window to show")
            return nil
        }

        logger.notice("Showing main window")

        // Ensure window moves to current Space (virtual desktop)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

        // Make key and bring to front
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        return window
    }

    /// Hides the main window.
    func hideMainWindow() {
        guard let window = resolveMainWindow() else { return }
        logger.notice("Hiding main window")
        window.orderOut(nil)
    }

    /// Returns the current main window if it exists.
    func currentMainWindow() -> NSWindow? {
        resolveMainWindow()
    }

    // MARK: - Private

    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }

        // Try to restore previous frame, otherwise center
        if !window.setFrameUsingName(Self.mainWindowAutosaveName) {
            window.center()
        }
        didApplyInitialPlacement = true
    }

    private func resolveMainWindow() -> NSWindow? {
        // Return cached window if still valid
        if let window = mainWindow {
            return window
        }

        // Search by identifier
        if let window = NSApplication.shared.windows.first(where: {
            $0.identifier == Self.mainWindowIdentifier
        }) {
            mainWindow = window
            window.delegate = self
            return window
        }

        return nil
    }
}

// MARK: - NSWindowDelegate

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }

        logger.notice("Main window will close")
        window.orderOut(nil)
        mainWindow = nil
        didApplyInitialPlacement = false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }

        // Ensure app is activated when window becomes key
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
