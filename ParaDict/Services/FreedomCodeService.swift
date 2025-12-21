import Foundation
import CryptoKit
import os

/// Service for generating and validating "freedom codes" that unlock the app after beta expiration.
/// Uses HMAC-SHA256 with a shared secret to create deterministic codes from email addresses.
struct FreedomCodeService {
    private static let logger = Logger(subsystem: "com.paradict", category: "FreedomCodeService")

    /// Shared secret for HMAC generation. Same value must be used in CLI tool.
    /// This is not meant to be cryptographically secure against reverse engineering,
    /// just a simple mechanism to generate valid codes.
    private static let secret = "ParaDict-Beta-Freedom-2024"

    /// Generate a freedom code for an email address.
    /// The code is the first 12 characters of HMAC-SHA256(secret, lowercase(email)), base32 encoded.
    static func generateCode(for email: String) -> String {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let key = SymmetricKey(data: Data(secret.utf8))
        let data = Data(normalizedEmail.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: key)

        // Convert to base32-like string (uppercase letters and digits, no ambiguous chars)
        let bytes = Array(hmac)
        let code = bytesToCode(bytes)

        logger.debug("Generated freedom code for email: \(normalizedEmail.prefix(3))***")
        return code
    }

    /// Validate that a code matches an email address.
    static func validate(code: String, for email: String) -> Bool {
        let expectedCode = generateCode(for: email)
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = normalizedCode == expectedCode

        if isValid {
            logger.notice("Freedom code validated successfully")
        } else {
            logger.notice("Freedom code validation failed")
        }

        return isValid
    }

    /// Convert HMAC bytes to a 12-character code using safe characters.
    /// Uses only uppercase letters (excluding O, I) and digits (excluding 0, 1).
    private static func bytesToCode(_ bytes: [UInt8]) -> String {
        // Safe alphabet: A-N, P-Z (no O), 2-9 (no 0, 1) = 32 characters
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        var result = ""
        for i in 0..<12 {
            let byte = bytes[i % bytes.count]
            let index = Int(byte) % alphabet.count
            result.append(alphabet[index])
        }

        // Format as XXX-XXX-XXX-XXX for readability
        let formatted = stride(from: 0, to: 12, by: 3).map { i in
            let start = result.index(result.startIndex, offsetBy: i)
            let end = result.index(start, offsetBy: 3)
            return String(result[start..<end])
        }.joined(separator: "-")

        return formatted
    }
}
