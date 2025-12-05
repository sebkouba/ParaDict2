import SwiftUI
import AVFoundation
import Cocoa
import Combine
import os

private let logger = Logger(subsystem: "com.paradict", category: "Permissions")

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isScreenRecordingEnabled = false

    init() {
        logger.notice("PermissionManager initializing...")
        setupNotificationObservers()
        checkAllPermissions()
    }

    var canRecord: Bool {
        audioPermissionStatus == .authorized
    }

    var canPaste: Bool {
        isAccessibilityEnabled
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        logger.notice("App became active - rechecking permissions")
        checkAllPermissions()
    }

    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
    }

    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        logger.notice("Accessibility check: \(accessibilityEnabled)")
        DispatchQueue.main.async {
            self.isAccessibilityEnabled = accessibilityEnabled
        }
    }

    func requestAccessibilityPermission() {
        logger.notice("Requesting accessibility permission (will prompt)")
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func checkScreenRecordingPermission() {
        let enabled = CGPreflightScreenCaptureAccess()
        logger.notice("Screen recording check: \(enabled)")
        DispatchQueue.main.async {
            self.isScreenRecordingEnabled = enabled
        }
    }

    func requestScreenRecordingPermission() {
        logger.notice("Requesting screen recording permission")
        CGRequestScreenCaptureAccess()
    }

    func checkAudioPermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.notice("Audio permission status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        DispatchQueue.main.async {
            self.audioPermissionStatus = status
        }
    }

    func requestAudioPermission() {
        logger.notice("Requesting audio permission...")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            logger.notice("Audio permission response: \(granted)")
            DispatchQueue.main.async {
                self.audioPermissionStatus = granted ? .authorized : .denied
            }
        }
    }

    @MainActor
    func requestAudioPermissionAsync() async -> Bool {
        logger.notice("Requesting audio permission (async)...")

        // If already authorized, return immediately
        if audioPermissionStatus == .authorized {
            logger.notice("Audio permission already authorized")
            return true
        }

        // If not determined, request it
        if audioPermissionStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.notice("Audio permission response: \(granted)")
            audioPermissionStatus = granted ? .authorized : .denied
            return granted
        }

        // Already denied or restricted
        logger.warning("Audio permission denied or restricted: \(self.audioPermissionStatus.rawValue)")
        return false
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let buttonAction: () -> Void
    let checkPermission: () -> Void

    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isRefreshing = true
                        }
                        checkPermission()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)

                    if isGranted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                    }
                }
            }

            if !isGranted {
                Button(action: buttonAction) {
                    HStack {
                        Text(buttonTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct PermissionsView: View {
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .padding(20)
                        .background(
                            Circle()
                                .fill(Color(NSColor.controlBackgroundColor))
                        )

                    VStack(spacing: 8) {
                        Text("App Permissions")
                            .font(.system(size: 28, weight: .bold))
                        Text("ParaDict requires the following permissions to function properly")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 40)

                // Permission Cards
                VStack(spacing: 16) {
                    // Audio Permission
                    PermissionCard(
                        icon: "mic",
                        title: "Microphone Access",
                        description: "Allow ParaDict to record your voice for transcription",
                        isGranted: permissionManager.audioPermissionStatus == .authorized,
                        buttonTitle: permissionManager.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings",
                        buttonAction: {
                            logger.notice("Audio permission button clicked - status: \(permissionManager.audioPermissionStatus.rawValue)")
                            if permissionManager.audioPermissionStatus == .notDetermined {
                                permissionManager.requestAudioPermission()
                            } else {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        },
                        checkPermission: { permissionManager.checkAudioPermissionStatus() }
                    )

                    // Accessibility Permission
                    PermissionCard(
                        icon: "hand.raised",
                        title: "Accessibility Access",
                        description: "Allow ParaDict to paste transcribed text at your cursor",
                        isGranted: permissionManager.isAccessibilityEnabled,
                        buttonTitle: "Open System Settings",
                        buttonAction: {
                            logger.notice("Accessibility permission button clicked")
                            permissionManager.requestAccessibilityPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkAccessibilityPermissions() }
                    )

                    // Screen Recording Permission (optional, for context)
                    PermissionCard(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Recording Access",
                        description: "Optional: Allows context-aware enhancement (not yet implemented)",
                        isGranted: permissionManager.isScreenRecordingEnabled,
                        buttonTitle: "Request Permission",
                        buttonAction: {
                            logger.notice("Screen recording permission button clicked")
                            permissionManager.requestScreenRecordingPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkScreenRecordingPermission() }
                    )
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            logger.notice("PermissionsView appeared")
            permissionManager.checkAllPermissions()
        }
    }
}

#Preview {
    PermissionsView()
}
