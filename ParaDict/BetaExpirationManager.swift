import Foundation
import Combine
import os

/// Manages beta expiration state and freedom code validation.
/// The app expires after a hardcoded date unless unlocked with a valid email + code combination.
@MainActor
class BetaExpirationManager: ObservableObject {
    static let shared = BetaExpirationManager()

    private let logger = Logger(subsystem: "com.paradict", category: "BetaExpirationManager")

    // MARK: - Beta Expiration Configuration

    /// The date when the beta expires. Update this for each beta release.
    /// Format: Year, Month, Day (midnight UTC)
    static let expirationDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components) ?? Date.distantFuture
    }()

    // MARK: - Published State

    @Published private(set) var isExpired: Bool = false
    @Published private(set) var isFreed: Bool = false
    @Published private(set) var daysRemaining: Int = 0
    @Published var freedomEmail: String = ""
    @Published var freedomCode: String = ""
    @Published var validationError: String?

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let freedEmail = "ParaDict.freed.email"
        static let freedCode = "ParaDict.freed.code"
    }

    // MARK: - Computed Properties

    /// Whether the app can be used (not expired, or has been freed)
    var canUseApp: Bool {
        isFreed || !isExpired
    }

    /// Human-readable expiration date
    var expirationDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Self.expirationDate)
    }

    /// Status message for display
    var statusMessage: String {
        if isFreed {
            return "App unlocked with freedom code"
        } else if isExpired {
            return "Beta expired on \(expirationDateString)"
        } else if daysRemaining <= 7 {
            return "Beta expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")"
        } else {
            return "Beta valid until \(expirationDateString)"
        }
    }

    // MARK: - Initialization

    private init() {
        loadState()
        logger.notice("BetaExpirationManager initialized: expired=\(self.isExpired), freed=\(self.isFreed), daysRemaining=\(self.daysRemaining)")
    }

    // MARK: - State Management

    private func loadState() {
        // Check if already freed
        if let savedEmail = UserDefaults.standard.string(forKey: Keys.freedEmail),
           let savedCode = UserDefaults.standard.string(forKey: Keys.freedCode) {
            // Validate the saved code still works
            if FreedomCodeService.validate(code: savedCode, for: savedEmail) {
                isFreed = true
                freedomEmail = savedEmail
                freedomCode = savedCode
                logger.notice("App is freed with saved code")
            } else {
                // Saved code no longer valid (shouldn't happen, but clear it)
                clearFreedomCode()
                logger.warning("Saved freedom code was invalid, cleared")
            }
        }

        // Calculate expiration state
        updateExpirationState()
    }

    private func updateExpirationState() {
        let now = Date()
        isExpired = now >= Self.expirationDate

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: now, to: Self.expirationDate)
        daysRemaining = max(0, components.day ?? 0)
    }

    // MARK: - Freedom Code Validation

    /// Attempt to validate and save a freedom code
    func validateAndSaveFreedomCode() -> Bool {
        validationError = nil

        // Validate email format
        let email = freedomEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            validationError = "Please enter your email address"
            return false
        }

        guard email.contains("@") && email.contains(".") else {
            validationError = "Please enter a valid email address"
            return false
        }

        // Validate code
        let code = freedomCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            validationError = "Please enter your freedom code"
            return false
        }

        // Check if code is valid
        if FreedomCodeService.validate(code: code, for: email) {
            // Save to UserDefaults
            UserDefaults.standard.set(email, forKey: Keys.freedEmail)
            UserDefaults.standard.set(code, forKey: Keys.freedCode)
            isFreed = true
            logger.notice("Freedom code validated and saved successfully")
            return true
        } else {
            validationError = "Invalid code. Please check your email and code."
            logger.notice("Freedom code validation failed for email: \(email.prefix(3))***")
            return false
        }
    }

    /// Clear the saved freedom code (for testing or reset)
    func clearFreedomCode() {
        UserDefaults.standard.removeObject(forKey: Keys.freedEmail)
        UserDefaults.standard.removeObject(forKey: Keys.freedCode)
        isFreed = false
        freedomEmail = ""
        freedomCode = ""
        validationError = nil
        updateExpirationState()
        logger.notice("Freedom code cleared")
    }
}
