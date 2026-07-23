import Combine
import Foundation
import os

enum ElevenLabsTranscriptionError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case emptyAudio
    case requestFailed(String)
    case invalidResponse
    case emptyResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "ElevenLabs API key not configured. Add your ElevenLabs API key in Settings."
        case .invalidAPIKey:
            return "Invalid ElevenLabs API key. Please check your ElevenLabs API key."
        case .emptyAudio:
            return "No audio was recorded."
        case .requestFailed(let message):
            return "ElevenLabs transcription failed: \(message)"
        case .invalidResponse:
            return "Invalid response from ElevenLabs transcription."
        case .emptyResponse:
            return "ElevenLabs returned an empty transcription."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class ElevenLabsTranscriptionService: ObservableObject {
    static let shared = ElevenLabsTranscriptionService()

    private let logger = Logger(subsystem: "com.paradict", category: "ElevenLabsTranscriptionService")
    private let sttURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    private let validationURL = URL(string: "https://api.elevenlabs.io/v1/user")!
    private let keychainAccount = "elevenlabs"
    private let keyStorage = APIKeyStorageService.shared
    private let sampleRate = 16_000
    private var cachedAPIKey: String?

    @Published var isAPIKeyValid = false
    @Published var isValidating = false
    @Published var lastValidationError: String?

    private init() {
        cachedAPIKey = Self.environmentAPIKey
        isAPIKeyValid = cachedAPIKey != nil
        Task { [weak self] in
            await self?.loadStoredAPIKey()
        }
    }

    var isConfigured: Bool {
        getStoredAPIKey() != nil
    }

    func getStoredAPIKey() -> String? {
        cachedAPIKey ?? Self.environmentAPIKey
    }

    func saveAPIKey(_ key: String) async -> Bool {
        let sanitizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedKey.isEmpty else {
            lastValidationError = ElevenLabsTranscriptionError.noAPIKey.localizedDescription
            return false
        }

        isValidating = true
        lastValidationError = nil
        defer { isValidating = false }

        do {
            guard try await validateAPIKey(sanitizedKey) else {
                lastValidationError = "ElevenLabs API key validation failed."
                isAPIKeyValid = false
                return false
            }

            try await keyStorage.saveKey(sanitizedKey, for: keychainAccount)
            cachedAPIKey = sanitizedKey
            isAPIKeyValid = true
            logger.notice("ElevenLabs API key saved and validated successfully")
            return true
        } catch {
            lastValidationError = error.localizedDescription
            isAPIKeyValid = false
            logger.error("ElevenLabs API key validation error: \(error.localizedDescription)")
            return false
        }
    }

    func clearAPIKey() async {
        do {
            try await keyStorage.deleteKey(for: keychainAccount)
            cachedAPIKey = nil
            isAPIKeyValid = Self.environmentAPIKey != nil
            lastValidationError = nil
            logger.notice("ElevenLabs API key cleared")
        } catch {
            isAPIKeyValid = getStoredAPIKey() != nil
            lastValidationError = error.localizedDescription
            logger.error("Unable to clear ElevenLabs API key from Keychain: \(error.localizedDescription)")
        }
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: validationURL)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ElevenLabsTranscriptionError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return true
            case 401, 403:
                throw ElevenLabsTranscriptionError.invalidAPIKey
            default:
                throw ElevenLabsTranscriptionError.requestFailed("HTTP \(httpResponse.statusCode)")
            }
        } catch let error as ElevenLabsTranscriptionError {
            throw error
        } catch {
            throw ElevenLabsTranscriptionError.networkError(error)
        }
    }

    func testConnection() async -> (success: Bool, message: String) {
        guard let key = await resolveAPIKey() else {
            return (false, ElevenLabsTranscriptionError.noAPIKey.localizedDescription)
        }

        do {
            let success = try await validateAPIKey(key)
            isAPIKeyValid = success
            return success ? (true, "Connection successful!") : (false, "Connection failed.")
        } catch {
            isAPIKeyValid = false
            return (false, error.localizedDescription)
        }
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        guard !audioSamples.isEmpty else {
            throw ElevenLabsTranscriptionError.emptyAudio
        }
        guard let apiKey = await resolveAPIKey() else {
            throw ElevenLabsTranscriptionError.noAPIKey
        }

        let body = Self.transcriptionBody(audioSamples: audioSamples)
        let boundary = body.boundary

        var request = URLRequest(url: sttURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body.data)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ElevenLabsTranscriptionError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw ElevenLabsTranscriptionError.invalidAPIKey
                }

                let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw ElevenLabsTranscriptionError.requestFailed("HTTP \(httpResponse.statusCode): \(message)")
            }

            let transcriptionResponse = try JSONDecoder().decode(ElevenLabsTranscriptionResponse.self, from: data)
            let text = transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ElevenLabsTranscriptionError.emptyResponse
            }

            let language = transcriptionResponse.languageCode ?? "unknown"
            logger.notice("ElevenLabs Scribe v2 transcription complete: \(text.count) chars, language \(language)")
            return text
        } catch let error as ElevenLabsTranscriptionError {
            throw error
        } catch let error as DecodingError {
            logger.error("Failed to decode ElevenLabs response: \(String(describing: error))")
            throw ElevenLabsTranscriptionError.invalidResponse
        } catch {
            throw ElevenLabsTranscriptionError.networkError(error)
        }
    }

    private func loadStoredAPIKey() async {
        do {
            if let storedKey = try await keyStorage.loadKey(for: keychainAccount) {
                cachedAPIKey = storedKey
            }
            isAPIKeyValid = getStoredAPIKey() != nil
        } catch {
            logger.error("Unable to load ElevenLabs API key from Keychain: \(error.localizedDescription)")
        }
    }

    private func resolveAPIKey() async -> String? {
        if let key = getStoredAPIKey() {
            return key
        }

        do {
            if let storedKey = try await keyStorage.loadKey(for: keychainAccount) {
                cachedAPIKey = storedKey
                isAPIKeyValid = true
                return storedKey
            }
        } catch {
            logger.error("Unable to resolve ElevenLabs API key from Keychain: \(error.localizedDescription)")
        }
        return nil
    }

    private static var environmentAPIKey: String? {
        ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func transcriptionBody(audioSamples: [Float]) -> (boundary: String, data: Data) {
        let boundary = "Boundary-\(UUID().uuidString)"
        let wavData = wavData(from: audioSamples, sampleRate: 16_000)
        let data = multipartBody(
            boundary: boundary,
            fields: [
                ("model_id", "scribe_v2"),
                ("tag_audio_events", "false"),
                ("diarize", "false"),
                ("timestamps_granularity", "none"),
                ("webhook", "false")
            ],
            fileFieldName: "file",
            fileName: "dictation.wav",
            mimeType: "audio/wav",
            fileData: wavData
        )
        return (boundary, data)
    }

#if DEBUG
    static func transcriptionBodyForTesting(audioSamples: [Float]) -> Data {
        transcriptionBody(audioSamples: audioSamples).data
    }
#endif

    private static func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()

        for (name, value) in fields {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        return body
    }

    private static func wavData(from samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt16(bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bytesPerSample)
        let blockAlign = channelCount * bytesPerSample
        let audioDataSize = UInt32(samples.count * Int(bytesPerSample))
        let chunkSize = UInt32(36) + audioDataSize

        data.appendUTF8("RIFF")
        data.appendLittleEndian(chunkSize)
        data.appendUTF8("WAVE")
        data.appendUTF8("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendUTF8("data")
        data.appendLittleEndian(audioDataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = clamped < 0 ? clamped * 32768.0 : clamped * 32767.0
            data.appendLittleEndian(Int16(scaled.rounded()))
        }

        return data
    }
}

private struct ElevenLabsTranscriptionResponse: Decodable {
    let text: String
    let languageCode: String?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
