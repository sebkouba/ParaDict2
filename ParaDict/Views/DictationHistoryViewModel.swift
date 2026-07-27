import AppKit
import Combine
import Foundation

@MainActor
final class DictationHistoryViewModel: ObservableObject {
    @Published private(set) var entries: [DictationHistoryService.Entry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var copiedEntryID: Int64?

    private let historyService: DictationHistoryService
    private var loadTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(historyService: DictationHistoryService = .shared) {
        self.historyService = historyService
    }

    func load(retentionLimit: Int) {
        loadTask?.cancel()
        isLoading = entries.isEmpty
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let loadedEntries = try await historyService.fetchEntries(
                    retentionLimit: retentionLimit
                )
                guard !Task.isCancelled else { return }

                entries = loadedEntries
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }

                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func applyRetentionLimit(_ retentionLimit: Int) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await historyService.applyRetentionLimit(retentionLimit)
                let loadedEntries = try await historyService.fetchEntries(
                    retentionLimit: retentionLimit
                )
                guard !Task.isCancelled else { return }

                entries = loadedEntries
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }

                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func filteredEntries(matching searchText: String) -> [DictationHistoryService.Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.finalText.localizedCaseInsensitiveContains(query)
                || entry.transcription.localizedCaseInsensitiveContains(query)
                || entry.modeDisplayName.localizedCaseInsensitiveContains(query)
                || entry.targetApp?.localizedCaseInsensitiveContains(query) == true
        }
    }

    func copy(_ entry: DictationHistoryService.Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.finalText, forType: .string)

        copiedEntryID = entry.id
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            if self?.copiedEntryID == entry.id {
                self?.copiedEntryID = nil
            }
        }
    }
}
