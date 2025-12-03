import Foundation
import Combine
import os

/// Activity log entry for UI display
struct WatcherActivity: Identifiable {
    let id = UUID()
    let timestamp: Date        // When processing completed
    let duration: TimeInterval // How long processing took
    let filename: String
    let outputFilename: String?
    let success: Bool
    let errorMessage: String?

    /// Formatted duration string (e.g., "2.3s" or "1m 23s")
    var formattedDuration: String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

/// Watches a directory for new audio files and transcribes them
class DirectoryWatcherService: ObservableObject {
    @MainActor static let shared = DirectoryWatcherService()

    private let logger = Logger(subsystem: "com.paradict", category: "DirectoryWatcher")

    @Published private(set) var isRunning = false
    @Published private(set) var recentActivity: [WatcherActivity] = []
    @Published private(set) var lastError: String?
    @Published private(set) var currentlyProcessing: String?  // filename being transcribed

    private var inputDirectory: URL?
    private var outputDirectory: URL?
    private var eventStream: FSEventStreamRef?
    private var processedFiles: [String: Date] = [:]  // path -> modification date
    private let fileEventQueue = DispatchQueue(label: "com.paradict.filewatcher", qos: .utility)

    private let supportedExtensions = ["wav", "mp3", "m4a", "aac", "flac", "ogg", "wma"]
    private let maxActivityHistory = 20

    enum DirectoryWatcherError: LocalizedError {
        case inputDirectoryNotSet
        case outputDirectoryNotSet
        case inputDirectoryDoesNotExist
        case fileNotStable
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .inputDirectoryNotSet:
                return "Input directory not configured"
            case .outputDirectoryNotSet:
                return "Output directory not configured"
            case .inputDirectoryDoesNotExist:
                return "Input directory does not exist"
            case .fileNotStable:
                return "File is still being written"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }

    private init() {
        loadProcessedFiles()
    }

    // MARK: - Public API

    @MainActor
    func start(inputDir: URL, outputDir: URL) {
        guard !isRunning else {
            logger.notice("Directory watcher already running")
            return
        }

        self.inputDirectory = inputDir
        self.outputDirectory = outputDir
        lastError = nil

        // Verify input directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputDir.path, isDirectory: &isDir), isDir.boolValue else {
            lastError = "Input directory does not exist: \(inputDir.path)"
            logger.error("Input directory does not exist: \(inputDir.path)")
            return
        }

        // Create output directory if needed
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            lastError = "Failed to create output directory: \(error.localizedDescription)"
            logger.error("Failed to create output directory: \(error.localizedDescription)")
            return
        }

        startFSEventStream(for: inputDir)
        isRunning = true
        logger.notice("Directory watcher started: \(inputDir.path) -> \(outputDir.path)")

        // Process any existing files in directory
        Task {
            await processExistingFiles()
        }
    }

    @MainActor
    func stop() {
        guard isRunning else { return }

        stopFSEventStream()
        isRunning = false
        logger.notice("Directory watcher stopped")
    }

    @MainActor
    func restart() {
        guard let inputDir = inputDirectory, let outputDir = outputDirectory else { return }
        stop()
        start(inputDir: inputDir, outputDir: outputDir)
    }

    // MARK: - FSEvents

    private func startFSEventStream(for directory: URL) {
        let pathsToWatch = [directory.path] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<DirectoryWatcherService>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

            Task.detached(priority: .userInitiated) {
                for path in paths {
                    await watcher.handleFileEvent(path: path)
                }
            }
        }

        eventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // Latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, fileEventQueue)
            FSEventStreamStart(stream)
        }
    }

    private func stopFSEventStream() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    // MARK: - File Processing

    private func handleFileEvent(path: String) async {
        let url = URL(fileURLWithPath: path)

        // Check if it's an audio file
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return
        }

        // Check if file exists (might be a delete event)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        // Check if already processed
        if isAlreadyProcessed(url: url) {
            return
        }

        logger.notice("New audio file detected: \(url.lastPathComponent)")

        // Process the file
        await processAudioFile(url: url)
    }

    private func processExistingFiles() async {
        guard let inputDir = inputDirectory else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: inputDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            for fileURL in contents {
                guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                    continue
                }

                if !isAlreadyProcessed(url: fileURL) {
                    await processAudioFile(url: fileURL)
                }
            }
        } catch {
            logger.error("Failed to scan existing files: \(error.localizedDescription)")
        }
    }

    private func processAudioFile(url: URL) async {
        let filename = url.lastPathComponent
        let startTime = Date()

        await MainActor.run {
            currentlyProcessing = filename
        }

        defer {
            Task { @MainActor in
                self.currentlyProcessing = nil
            }
        }

        do {
            // Wait for file to be stable (fully written)
            try await waitForFileStability(url: url)

            // Convert to WAV if needed
            let wavURL: URL
            let needsCleanup: Bool

            if AudioConverterService.shared.isCompatibleWAV(url: url) {
                wavURL = url
                needsCleanup = false
                logger.notice("File is already compatible WAV: \(filename)")
            } else {
                wavURL = try await AudioConverterService.shared.convertToWAV(inputURL: url)
                needsCleanup = true
                logger.notice("Converted to WAV: \(filename)")
            }

            // Transcribe using background instance to avoid blocking live dictation
            logger.notice("Transcribing: \(filename)")
            let transcription = try await ParakeetTranscriptionService.background.transcribe(audioURL: wavURL)

            // Clean up temp file if we converted
            if needsCleanup {
                AudioConverterService.shared.cleanupTempFile(wavURL)
            }

            // Write output
            let outputFilename = url.deletingPathExtension().lastPathComponent + ".txt"
            guard let outputDir = outputDirectory else {
                throw DirectoryWatcherError.outputDirectoryNotSet
            }
            let outputURL = outputDir.appendingPathComponent(outputFilename)

            try transcription.write(to: outputURL, atomically: true, encoding: .utf8)
            logger.notice("Transcription saved: \(outputFilename)")

            // Mark as processed
            markAsProcessed(url: url)

            // Add to activity log with duration (on main thread)
            let duration = Date().timeIntervalSince(startTime)
            await MainActor.run {
                addActivity(filename: filename, outputFilename: outputFilename, success: true, duration: duration)
            }

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Failed to process \(filename): \(error.localizedDescription)")
            await MainActor.run {
                addActivity(filename: filename, outputFilename: nil, success: false, errorMessage: error.localizedDescription, duration: duration)
            }
        }
    }

    private func waitForFileStability(url: URL) async throws {
        var lastSize: Int64 = -1

        for _ in 0..<10 {  // Max 5 seconds total
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int64 ?? 0

            if size == lastSize && size > 0 {
                return  // File is stable
            }

            lastSize = size
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second
        }

        throw DirectoryWatcherError.fileNotStable
    }

    // MARK: - Processed Files Tracking

    private func isAlreadyProcessed(url: URL) -> Bool {
        let path = url.path

        guard let modDate = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date else {
            return false
        }

        if let processedDate = processedFiles[path], processedDate == modDate {
            return true
        }

        return false
    }

    private func markAsProcessed(url: URL) {
        let path = url.path

        if let modDate = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date {
            processedFiles[path] = modDate
            saveProcessedFiles()
        }
    }

    private var processedFilesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ParaDict/watcher_processed.json")
    }

    private func loadProcessedFiles() {
        guard FileManager.default.fileExists(atPath: processedFilesURL.path) else { return }

        do {
            let data = try Data(contentsOf: processedFilesURL)
            let decoded = try JSONDecoder().decode([String: Date].self, from: data)
            processedFiles = decoded
            logger.notice("Loaded \(self.processedFiles.count) processed file records")
        } catch {
            logger.error("Failed to load processed files: \(error.localizedDescription)")
        }
    }

    private func saveProcessedFiles() {
        do {
            let data = try JSONEncoder().encode(processedFiles)
            try data.write(to: processedFilesURL)
        } catch {
            logger.error("Failed to save processed files: \(error.localizedDescription)")
        }
    }

    // MARK: - Activity Log

    @MainActor
    private func addActivity(filename: String, outputFilename: String?, success: Bool, errorMessage: String? = nil, duration: TimeInterval) {
        let activity = WatcherActivity(
            timestamp: Date(),
            duration: duration,
            filename: filename,
            outputFilename: outputFilename,
            success: success,
            errorMessage: errorMessage
        )

        recentActivity.insert(activity, at: 0)

        // Keep only recent history
        if recentActivity.count > maxActivityHistory {
            recentActivity = Array(recentActivity.prefix(maxActivityHistory))
        }
    }

    @MainActor
    func clearActivity() {
        recentActivity.removeAll()
    }

    @MainActor
    func clearProcessedFiles() {
        processedFiles.removeAll()
        try? FileManager.default.removeItem(at: processedFilesURL)
        logger.notice("Cleared processed files history")
    }
}
