#!/usr/bin/env swift

/// Freedom Code Generator for ParaDict Beta
///
/// Usage:
///   swift generate-freedom-code.swift <email>
///   swift generate-freedom-code.swift user@example.com
///
/// The generated code can be given to users to unlock their expired beta.

import Foundation
import CryptoKit

// MARK: - Configuration

/// Shared secret - MUST match the value in FreedomCodeService.swift
let secret = "ParaDict-Beta-Freedom-2024"

// MARK: - Code Generation

func generateCode(for email: String) -> String {
    let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let key = SymmetricKey(data: Data(secret.utf8))
    let data = Data(normalizedEmail.utf8)
    let hmac = HMAC<SHA256>.authenticationCode(for: data, using: key)

    // Convert to code
    let bytes = Array(hmac)
    return bytesToCode(bytes)
}

func bytesToCode(_ bytes: [UInt8]) -> String {
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

// MARK: - Main

func printUsage() {
    print("""
    ParaDict Freedom Code Generator

    Usage:
      swift \(CommandLine.arguments[0]) <email>

    Examples:
      swift \(CommandLine.arguments[0]) user@example.com
      swift \(CommandLine.arguments[0]) "John Doe <john@example.com>"

    The generated code unlocks ParaDict after beta expiration.
    """)
}

func main() {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        printUsage()
        exit(1)
    }

    // Handle --help flag
    if args[1] == "--help" || args[1] == "-h" {
        printUsage()
        exit(0)
    }

    // Handle batch mode (multiple emails)
    if args[1] == "--batch" {
        print("Batch mode: Enter emails (one per line), Ctrl+D to finish:\n")
        while let line = readLine() {
            let email = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty {
                let code = generateCode(for: email)
                print("\(email) -> \(code)")
            }
        }
        exit(0)
    }

    // Single email mode
    let email = args[1]
    let code = generateCode(for: email)

    print("""

    Email: \(email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    Code:  \(code)

    """)
}

main()
