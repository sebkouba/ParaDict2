import SwiftUI

/// View for displaying beta expiration status and freedom code entry.
/// Can be used as a settings tab or as a blocking modal when expired.
struct BetaLicenseView: View {
    @StateObject private var expirationManager = BetaExpirationManager.shared
    @State private var showingCodeEntry = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: expirationManager.isFreed ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundColor(statusColor)

                Text(expirationManager.isFreed ? "App Unlocked" : "Beta Version")
                    .font(.title)
                    .fontWeight(.semibold)

                Text(expirationManager.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)

            Divider()

            if expirationManager.isFreed {
                // Show freed status
                FreedStatusView(expirationManager: expirationManager)
            } else if expirationManager.isExpired {
                // Show expired state with code entry
                ExpiredView(expirationManager: expirationManager)
            } else {
                // Show active beta info
                ActiveBetaView(expirationManager: expirationManager, showingCodeEntry: $showingCodeEntry)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusColor: Color {
        if expirationManager.isFreed {
            return .green
        } else if expirationManager.isExpired {
            return .red
        } else if expirationManager.daysRemaining <= 7 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Subviews

private struct FreedStatusView: View {
    @ObservedObject var expirationManager: BetaExpirationManager

    var body: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlocked with", systemImage: "envelope")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(expirationManager.freedomEmail)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Button("Remove License") {
                expirationManager.clearFreedomCode()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding(.horizontal)
    }
}

private struct ExpiredView: View {
    @ObservedObject var expirationManager: BetaExpirationManager
    @FocusState private var focusedField: Field?

    enum Field {
        case email, code
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("This beta version has expired. Enter your freedom code to continue using the app, or download the latest version.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            FreedomCodeEntryForm(expirationManager: expirationManager)

            Divider()

            Button("Check for Updates") {
                // TODO: Add update URL when available
                if let url = URL(string: "https://github.com/sebkouba/ParaDict2/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ActiveBetaView: View {
    @ObservedObject var expirationManager: BetaExpirationManager
    @Binding var showingCodeEntry: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator
            if expirationManager.daysRemaining > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(expirationManager.daysRemaining), total: 90)
                        .progressViewStyle(.linear)
                        .tint(expirationManager.daysRemaining <= 7 ? .orange : .blue)

                    Text("\(expirationManager.daysRemaining) days remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            Text("Thank you for testing ParaDict! This beta version will expire on \(expirationManager.expirationDateString).")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Toggle to show code entry
            DisclosureGroup("Have a freedom code?", isExpanded: $showingCodeEntry) {
                FreedomCodeEntryForm(expirationManager: expirationManager)
                    .padding(.top, 8)
            }
            .padding(.horizontal)
        }
    }
}

private struct FreedomCodeEntryForm: View {
    @ObservedObject var expirationManager: BetaExpirationManager
    @FocusState private var focusedField: Field?

    enum Field {
        case email, code
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Email")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("your@email.com", text: $expirationManager.freedomEmail)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .code }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Freedom Code")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("XXX-XXX-XXX-XXX", text: $expirationManager.freedomCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedField, equals: .code)
                    .onSubmit { validateCode() }
            }

            if let error = expirationManager.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button("Unlock App") {
                validateCode()
            }
            .buttonStyle(.borderedProminent)
            .disabled(expirationManager.freedomEmail.isEmpty || expirationManager.freedomCode.isEmpty)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func validateCode() {
        _ = expirationManager.validateAndSaveFreedomCode()
    }
}

// MARK: - Blocking Modal View (for expired state)

/// A full-screen blocking view shown when the beta has expired
struct BetaExpiredBlockingView: View {
    @StateObject private var expirationManager = BetaExpirationManager.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Beta Expired")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("This beta version of ParaDict expired on \(expirationManager.expirationDateString).")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Divider()
                .padding(.horizontal, 60)

            // Freedom code entry
            VStack(spacing: 16) {
                Text("Enter your freedom code to continue:")
                    .font(.headline)

                FreedomCodeEntryForm(expirationManager: expirationManager)
                    .frame(maxWidth: 400)
            }

            Divider()
                .padding(.horizontal, 60)

            // Alternative: check for updates
            VStack(spacing: 8) {
                Text("Or download the latest version:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Check for Updates") {
                    if let url = URL(string: "https://github.com/sebkouba/ParaDict2/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("Active Beta") {
    BetaLicenseView()
}

#Preview("Expired Blocking") {
    BetaExpiredBlockingView()
}
