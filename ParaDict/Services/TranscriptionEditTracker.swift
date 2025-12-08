import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.paradict", category: "TranscriptionEditTracker")

/// Tracks user edits to pasted transcriptions using macOS Accessibility APIs.
/// When a transcription is pasted, this service monitors the target text element
/// for changes and logs any edits for later analysis.
class TranscriptionEditTracker {
    static let shared = TranscriptionEditTracker()

    /// Represents an active monitoring session for a pasted transcription
    private struct MonitoringSession {
        let id: UUID
        let transcribedText: String       // What we transcribed and pasted
        let elementValueAtStart: String   // Full value of text element when tracking started
        let transcriptionStartIndex: Int  // Where our transcription starts in the element value
        let transcriptionEndIndex: Int    // Where our transcription ends in the element value
        let timestamp: Date
        let appBundleId: String
        let targetAppPid: pid_t           // PID of the app we pasted into
        let element: AXUIElement
        let elementDescription: String    // Role/description for logging
        var observer: AXObserver?
        var focusObserver: AXObserver?    // Observer for focus changes within the app
        var timeoutWorkItem: DispatchWorkItem?
    }

    /// Active monitoring sessions keyed by session ID
    private var sessions: [UUID: MonitoringSession] = [:]

    /// Lock for thread-safe access to sessions
    private let sessionsLock = NSLock()

    /// Workspace notification observer
    private var workspaceObserver: NSObjectProtocol?

    /// Timeout duration in seconds
    private let timeoutDuration: TimeInterval = 60.0

    /// Log file path
    private var logFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("ParaDict")
        return appDir.appendingPathComponent("transcription_edits.log")
    }

    private init() {
        ensureLogDirectoryExists()
        setupWorkspaceObserver()
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Set up observer for app activation changes
    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
        logger.notice("Workspace observer set up for app activation changes")
    }

    /// Handle when a different app becomes active
    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let activatedBundleId = app.bundleIdentifier else {
            return
        }

        logger.notice("App activated: \(activatedBundleId)")

        // Check if any sessions are for a different app than what just activated
        sessionsLock.lock()
        let sessionsToEnd = sessions.filter { _, session in
            session.appBundleId != activatedBundleId
        }
        sessionsLock.unlock()

        for (sessionId, session) in sessionsToEnd {
            logger.notice("Ending session \(sessionId.uuidString) - different app activated (was: \(session.appBundleId), now: \(activatedBundleId))")
            endSession(sessionId, reason: "app switched (from \(session.appBundleId) to \(activatedBundleId))")
        }
    }

    /// Start tracking edits for a pasted transcription.
    /// Call this after pasting text to begin monitoring.
    func startTracking(originalText: String) {
        guard AXIsProcessTrusted() else {
            logger.warning("Cannot track edits - accessibility not trusted")
            return
        }

        logger.notice("========== START TRACKING ==========")
        logger.notice("Transcribed text (\(originalText.count) chars): \(originalText)")

        // Get the focused element in the frontmost app
        guard let focusedElement = getFocusedTextElement(),
              let appBundleId = getFrontmostAppBundleId(),
              let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("Could not get focused text element or app bundle ID")
            return
        }

        let targetPid = frontmostApp.processIdentifier

        // Get element info for debugging
        let elementRole = getElementAttribute(focusedElement, attribute: kAXRoleAttribute) ?? "unknown"
        let elementRoleDesc = getElementAttribute(focusedElement, attribute: kAXRoleDescriptionAttribute) ?? ""
        let elementTitle = getElementAttribute(focusedElement, attribute: kAXTitleAttribute) ?? ""
        let elementDesc = "[\(elementRole)] \(elementRoleDesc) - \(elementTitle)"

        logger.notice("Focused element: \(elementDesc)")
        logger.notice("Target app: \(appBundleId)")

        // Get current value of the element
        let currentValue = getElementValue(focusedElement) ?? ""
        logger.notice("Element value at start (\(currentValue.count) chars):")
        // Log first and last 100 chars if long
        if currentValue.count > 250 {
            logger.notice("  First 100: \(currentValue.prefix(100))")
            logger.notice("  Last 100: \(currentValue.suffix(100))")
        } else {
            logger.notice("  \(currentValue)")
        }

        // Find where our transcription appears in the element value
        var transcriptionStart = 0
        var transcriptionEnd = currentValue.count
        if let range = currentValue.range(of: originalText) {
            transcriptionStart = currentValue.distance(from: currentValue.startIndex, to: range.lowerBound)
            transcriptionEnd = currentValue.distance(from: currentValue.startIndex, to: range.upperBound)
            logger.notice("Transcription found at position \(transcriptionStart)-\(transcriptionEnd)")
        } else {
            // Transcription not found exactly - might have been modified during paste
            // Try to find the end of the text (our transcription was probably appended)
            logger.notice("Transcription not found exactly in element value - assuming at end")
            transcriptionStart = max(0, currentValue.count - originalText.count)
            transcriptionEnd = currentValue.count
        }

        let sessionId = UUID()
        logger.notice("Session ID: \(sessionId.uuidString)")

        // Create the monitoring session
        var session = MonitoringSession(
            id: sessionId,
            transcribedText: originalText,
            elementValueAtStart: currentValue,
            transcriptionStartIndex: transcriptionStart,
            transcriptionEndIndex: transcriptionEnd,
            timestamp: Date(),
            appBundleId: appBundleId,
            targetAppPid: targetPid,
            element: focusedElement,
            elementDescription: elementDesc,
            observer: nil,
            focusObserver: nil,
            timeoutWorkItem: nil
        )

        // Set up AXObserver for value changes
        if let observer = createObserver(for: focusedElement, sessionId: sessionId, appBundleId: appBundleId) {
            session.observer = observer
        } else {
            logger.warning("Could not create AXObserver for value changes")
        }

        // Set up AXObserver for focus changes within the app
        if let focusObserver = createFocusObserver(pid: targetPid, sessionId: sessionId) {
            session.focusObserver = focusObserver
        } else {
            logger.warning("Could not create AXObserver for focus changes")
        }

        // Set up timeout
        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.endSession(sessionId, reason: "timeout (60s)")
        }
        session.timeoutWorkItem = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutWork)

        // Store the session
        sessionsLock.lock()
        sessions[sessionId] = session
        sessionsLock.unlock()

        logger.notice("Session started - monitoring for app switch and focus changes")
    }

    /// End a monitoring session and log any edits
    private func endSession(_ sessionId: UUID, reason: String = "unknown") {
        sessionsLock.lock()
        guard let session = sessions.removeValue(forKey: sessionId) else {
            sessionsLock.unlock()
            logger.notice("Session \(sessionId.uuidString) already ended")
            return
        }
        sessionsLock.unlock()

        logger.notice("========== END SESSION ==========")
        logger.notice("Session ID: \(sessionId.uuidString)")
        logger.notice("End reason: \(reason)")
        logger.notice("Element was: \(session.elementDescription)")
        logger.notice("App: \(session.appBundleId)")

        // Cancel timeout if still pending
        session.timeoutWorkItem?.cancel()

        // Remove value observer
        if let observer = session.observer {
            AXObserverRemoveNotification(observer, session.element, kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }

        // Remove focus observer
        if let focusObserver = session.focusObserver {
            let appElement = AXUIElementCreateApplication(session.targetAppPid)
            AXObserverRemoveNotification(focusObserver, appElement, kAXFocusedUIElementChangedNotification as CFString)
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(focusObserver),
                .defaultMode
            )
        }

        // Get final value
        let finalText = getElementValue(session.element)
        logger.notice("Transcribed text was (\(session.transcribedText.count) chars): \(session.transcribedText)")
        logger.notice("Transcription was at position \(session.transcriptionStartIndex)-\(session.transcriptionEndIndex)")

        if let finalText = finalText {
            logger.notice("Element value at END (\(finalText.count) chars)")

            // Check if the transcribed text still exists exactly
            if finalText.contains(session.transcribedText) {
                logger.notice("Transcription unchanged - found exact match in final text")
                logger.notice("=================================")
                return
            }

            // The transcription was edited - try to find what it became
            // Strategy: Look at the region around where we pasted and find the edited version
            let editedText = extractEditedTranscription(
                originalTranscription: session.transcribedText,
                originalPosition: session.transcriptionStartIndex,
                originalLength: session.transcribedText.count,
                startValue: session.elementValueAtStart,
                endValue: finalText
            )

            if let editedText = editedText {
                logger.notice("Extracted edited transcription: \(editedText)")

                // Only log if actually different
                if editedText != session.transcribedText {
                    logger.notice("EDIT DETECTED:")
                    logger.notice("  Original: \(session.transcribedText)")
                    logger.notice("  Edited:   \(editedText)")
                    logEdit(
                        timestamp: session.timestamp,
                        original: session.transcribedText,
                        edited: editedText,
                        appBundleId: session.appBundleId
                    )
                } else {
                    logger.notice("Extracted text matches original - no edit")
                }
            } else {
                logger.notice("Could not extract edited transcription - transcription may have been deleted")
            }
        } else {
            logger.notice("Could not get final value - element may no longer exist")
        }
        logger.notice("=================================")
    }

    /// End all active sessions (e.g., on app termination)
    func endAllSessions() {
        sessionsLock.lock()
        let sessionIds = Array(sessions.keys)
        sessionsLock.unlock()

        for sessionId in sessionIds {
            endSession(sessionId)
        }
    }

    // MARK: - Accessibility Helpers

    /// Get the focused text element in the frontmost application
    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appResult == .success, let app = focusedApp else {
            logger.warning("Could not get focused application: \(appResult.rawValue)")
            return nil
        }

        // Get the focused UI element within that app
        // swiftlint:disable:next force_cast
        // Safe: AXUIElementCopyAttributeValue guarantees AXUIElement type for app attributes
        let appElement = app as! AXUIElement

        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard elementResult == .success, let element = focusedElement else {
            logger.warning("Could not get focused UI element: \(elementResult.rawValue)")
            return nil
        }

        // swiftlint:disable:next force_cast
        // Safe: When elementResult == .success, the returned value is guaranteed to be AXUIElement
        return (element as! AXUIElement)
    }

    /// Get the bundle ID of the frontmost application
    private func getFrontmostAppBundleId() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Get the value of a text element
    private func getElementValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let stringValue = value as? String else {
            return nil
        }
        return stringValue
    }

    /// Get a string attribute from an element
    private func getElementAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// Extract the edited version of a transcription from the final text
    /// by comparing the region around where we originally pasted
    private func extractEditedTranscription(
        originalTranscription: String,
        originalPosition: Int,
        originalLength: Int,
        startValue: String,
        endValue: String
    ) -> String? {
        logger.notice("Extracting edited transcription...")
        logger.notice("  Original position: \(originalPosition), length: \(originalLength)")

        // Get the prefix (text before our transcription) from the start value
        let prefixEndIndex = startValue.index(startValue.startIndex, offsetBy: min(originalPosition, startValue.count))
        let prefix = String(startValue[..<prefixEndIndex])
        logger.notice("  Prefix (\(prefix.count) chars): '\(prefix.suffix(50))'")

        // Get the suffix (text after our transcription) from the start value
        let suffixStartOffset = min(originalPosition + originalLength, startValue.count)
        let suffixStartIndex = startValue.index(startValue.startIndex, offsetBy: suffixStartOffset)
        let suffix = String(startValue[suffixStartIndex...])
        logger.notice("  Suffix (\(suffix.count) chars): '\(suffix.prefix(50))'")

        // Find where the prefix ends in the final text
        // The prefix should be unchanged, so we look for it at the same position
        var editedStart = originalPosition

        // If the prefix is non-empty, try to find it in the end value
        if !prefix.isEmpty {
            // Look for the prefix in the end value (it should be at the start or near start)
            if let prefixRange = endValue.range(of: prefix) {
                editedStart = endValue.distance(from: endValue.startIndex, to: prefixRange.upperBound)
                logger.notice("  Found prefix in final text, edited region starts at \(editedStart)")
            } else {
                // Prefix not found exactly - maybe user edited before the transcription too
                // Fall back to using original position
                logger.notice("  Prefix not found in final text - using original position")
            }
        }

        // Find where the edited transcription ends
        // Strategy: Look for the suffix, or find a line boundary, or use approximate length
        var editedEnd = endValue.count

        // Early bounds check - if editedStart is beyond endValue, we can't extract anything
        guard editedStart < endValue.count else {
            logger.notice("  editedStart (\(editedStart)) >= endValue.count (\(endValue.count)) - cannot extract")
            return nil
        }

        if !suffix.isEmpty {
            // Look for the suffix in the end value starting from editedStart
            let searchStart = endValue.index(endValue.startIndex, offsetBy: editedStart)
            if let suffixRange = endValue.range(of: suffix, range: searchStart..<endValue.endIndex) {
                editedEnd = endValue.distance(from: endValue.startIndex, to: suffixRange.lowerBound)
                logger.notice("  Found suffix in final text, edited region ends at \(editedEnd)")
            } else {
                // Suffix not found - user might have added text after
                // Look for a line break or use approximate position
                let approxEnd = min(editedStart + originalLength + 50, endValue.count)  // Allow some growth
                let searchEndIndex = endValue.index(endValue.startIndex, offsetBy: approxEnd)
                let searchRegion = endValue[endValue.index(endValue.startIndex, offsetBy: editedStart)..<searchEndIndex]

                // Find the first line break after the expected end
                if let newlineRange = searchRegion.range(of: "\n") {
                    editedEnd = endValue.distance(from: endValue.startIndex, to: newlineRange.lowerBound)
                    logger.notice("  Using line break as end boundary at \(editedEnd)")
                } else {
                    editedEnd = approxEnd
                    logger.notice("  Using approximate end at \(editedEnd)")
                }
            }
        }

        // Extract the edited region
        guard editedStart < editedEnd && editedStart < endValue.count else {
            logger.notice("  Invalid region: start=\(editedStart), end=\(editedEnd), length=\(endValue.count)")
            return nil
        }

        let extractStart = endValue.index(endValue.startIndex, offsetBy: editedStart)
        let extractEnd = endValue.index(endValue.startIndex, offsetBy: min(editedEnd, endValue.count))
        let extracted = String(endValue[extractStart..<extractEnd])

        logger.notice("  Extracted region (\(extracted.count) chars): '\(extracted)'")
        return extracted
    }

    /// Create an AXObserver for value changes
    private func createObserver(for element: AXUIElement, sessionId: UUID, appBundleId: String) -> AXObserver? {
        // Get the PID of the target app
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        guard pidResult == .success else {
            logger.warning("Could not get PID for element: \(pidResult.rawValue)")
            return nil
        }

        // Create observer
        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            // This callback is called when the value changes
            guard let refcon = refcon else { return }
            let sessionIdPtr = refcon.assumingMemoryBound(to: UUID.self)
            let sessionId = sessionIdPtr.pointee

            logger.debug("AXValueChanged notification for session \(sessionId.uuidString)")
            // We don't need to do anything here - we'll get the final value when the session ends
        }, &observer)

        guard createResult == .success, let obs = observer else {
            logger.warning("Could not create AXObserver: \(createResult.rawValue)")
            return nil
        }

        // Store session ID in a way the callback can access
        // Note: We use the session ID from the sessions dictionary, so we don't need refcon

        // Add notification for value changes
        let addResult = AXObserverAddNotification(obs, element, kAXValueChangedNotification as CFString, nil)
        if addResult != .success {
            logger.warning("Could not add value changed notification: \(addResult.rawValue)")
            // Continue anyway - timeout will still work
        }

        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        logger.notice("AXObserver created and added to run loop for PID \(pid)")
        return obs
    }

    /// Create an AXObserver for focus changes within the target app
    private func createFocusObserver(pid: pid_t, sessionId: UUID) -> AXObserver? {
        var observer: AXObserver?

        // Create callback that will be called on focus change
        let callback: AXObserverCallback = { (observer, element, notification, refcon) in
            logger.notice("Focus changed within app - notification received")

            // Find and end any sessions for this app
            // We need to dispatch to main queue since we can't safely access self from the callback
            DispatchQueue.main.async {
                TranscriptionEditTracker.shared.handleFocusChange()
            }
        }

        let createResult = AXObserverCreate(pid, callback, &observer)
        guard createResult == .success, let obs = observer else {
            logger.warning("Could not create focus AXObserver: \(createResult.rawValue)")
            return nil
        }

        // Get the app element to observe
        let appElement = AXUIElementCreateApplication(pid)

        // Add notification for focus changes
        let addResult = AXObserverAddNotification(obs, appElement, kAXFocusedUIElementChangedNotification as CFString, nil)
        if addResult != .success {
            logger.warning("Could not add focus changed notification: \(addResult.rawValue)")
            return nil
        }

        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        logger.notice("Focus observer created for PID \(pid)")
        return obs
    }

    /// Handle focus change within an app - end all sessions for that app
    fileprivate func handleFocusChange() {
        logger.notice("Handling focus change event")

        sessionsLock.lock()
        let allSessions = Array(sessions.values)
        sessionsLock.unlock()

        for session in allSessions {
            logger.notice("Ending session \(session.id.uuidString) due to focus change within app")
            endSession(session.id, reason: "focus changed within app")
        }
    }

    // MARK: - Logging

    /// Ensure the log directory exists
    private func ensureLogDirectoryExists() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = appSupport.appendingPathComponent("ParaDict")

        if !FileManager.default.fileExists(atPath: appDir.path) {
            do {
                try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
                logger.notice("Created app support directory")
            } catch {
                logger.error("Failed to create app support directory: \(error.localizedDescription)")
            }
        }
    }

    /// Log an edit to the transcription edits log file
    private func logEdit(timestamp: Date, original: String, edited: String, appBundleId: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampStr = formatter.string(from: timestamp)

        // Escape newlines and tabs in the text
        let escapedOriginal = original
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        let escapedEdited = edited
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        let logLine = "\(timestampStr)\t\(escapedOriginal)\t\(escapedEdited)\t\(appBundleId)\n"

        do {
            if FileManager.default.fileExists(atPath: logFilePath.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: logFilePath)
                fileHandle.seekToEndOfFile()
                if let data = logLine.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                // Create new file
                try logLine.write(to: logFilePath, atomically: true, encoding: .utf8)
            }
            logger.notice("Logged edit to \(self.logFilePath.path)")
        } catch {
            logger.error("Failed to log edit: \(error.localizedDescription)")
        }
    }
}
