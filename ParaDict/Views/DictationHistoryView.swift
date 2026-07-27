import SwiftUI

struct DictationHistoryView: View {
    @StateObject private var viewModel = DictationHistoryViewModel()
    @AppStorage(SettingsKeys.dictationHistoryRetentionLimit)
    private var retentionLimit = SettingsDefaults.dictationHistoryRetentionLimit

    @State private var searchText = ""
    @State private var pendingRetentionLimit: Int?
    @State private var isConfirmingRetentionChange = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 4)
                .padding(.bottom, 14)

            Divider()

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            viewModel.load(retentionLimit: retentionLimit)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictationHistoryDidChange)) { _ in
            viewModel.load(retentionLimit: retentionLimit)
        }
        .alert(
            retentionConfirmationTitle,
            isPresented: $isConfirmingRetentionChange
        ) {
            Button("Cancel", role: .cancel) {
                pendingRetentionLimit = nil
            }
            Button("Remove Older Entries", role: .destructive) {
                guard let pendingRetentionLimit else { return }
                applyRetentionLimit(pendingRetentionLimit)
                self.pendingRetentionLimit = nil
            }
        } message: {
            Text(
                "Older entries will be permanently removed from ParaDict's history database. This cannot be undone."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Dictation History", systemImage: "clock.arrow.circlepath")
                        .font(.title2.weight(.semibold))

                    Text(historySummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Keep", selection: retentionSelection) {
                    ForEach(DictationHistoryService.RetentionLimit.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .frame(width: 210)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search dictations", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            Text("“All dictations” keeps every entry. Choosing a limit permanently removes older entries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        let matchingEntries = filteredEntries

        if viewModel.isLoading && viewModel.entries.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading dictation history…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "History Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if matchingEntries.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Dictations Yet" : "No Matching Dictations",
                systemImage: searchText.isEmpty ? "text.bubble" : "magnifyingglass",
                description: Text(
                    searchText.isEmpty
                        ? "Completed dictations will appear here."
                        : "Try a different search."
                )
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matchingEntries) { entry in
                        entryRow(entry)

                        if entry.id != matchingEntries.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var filteredEntries: [DictationHistoryService.Entry] {
        viewModel.filteredEntries(matching: searchText)
    }

    private var historySummary: String {
        let count = viewModel.entries.count
        return "\(count.formatted()) saved dictation\(count == 1 ? "" : "s")"
    }

    private var retentionSelection: Binding<Int> {
        Binding(
            get: { retentionLimit },
            set: { requestedLimit in
                guard requestedLimit != retentionLimit else { return }

                if requestedLimit > 0, viewModel.entries.count > requestedLimit {
                    pendingRetentionLimit = requestedLimit
                    isConfirmingRetentionChange = true
                } else {
                    applyRetentionLimit(requestedLimit)
                }
            }
        )
    }

    private var retentionConfirmationTitle: String {
        guard let pendingRetentionLimit else {
            return "Limit Dictation History?"
        }
        return "Keep Only the Last \(pendingRetentionLimit.formatted()) Dictations?"
    }

    private func applyRetentionLimit(_ newLimit: Int) {
        retentionLimit = newLimit
        viewModel.applyRetentionLimit(newLimit)
    }

    private func entryRow(_ entry: DictationHistoryService.Entry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(
                    entry.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(entry.modeDisplayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Spacer()

                Button {
                    viewModel.copy(entry)
                } label: {
                    Label(
                        viewModel.copiedEntryID == entry.id ? "Copied" : "Copy",
                        systemImage: viewModel.copiedEntryID == entry.id
                            ? "checkmark"
                            : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy this dictation to the clipboard")
            }

            Text(entry.finalText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.enhancedText != nil, entry.transcription != entry.finalText {
                DisclosureGroup("Original transcription") {
                    Text(entry.transcription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button("Copy Dictation") {
                viewModel.copy(entry)
            }
        }
    }
}

#Preview {
    DictationHistoryView()
        .frame(width: 760, height: 560)
        .padding()
}
