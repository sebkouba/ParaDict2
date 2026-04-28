import Foundation
import Combine
import os

enum XAITranscriptionError: LocalizedError {
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
            return "x.ai API key not configured. Add your x.ai API key in Settings."
        case .invalidAPIKey:
            return "Invalid x.ai API key. Please check your x.ai API key."
        case .emptyAudio:
            return "No audio was recorded."
        case .requestFailed(let message):
            return "x.ai transcription failed: \(message)"
        case .invalidResponse:
            return "Invalid response from x.ai transcription."
        case .emptyResponse:
            return "x.ai returned an empty transcription."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
class XAITranscriptionService: ObservableObject {
    static let shared = XAITranscriptionService()

    private let logger = Logger(subsystem: "com.paradict", category: "XAITranscriptionService")
    private let sttURL = URL(string: "https://api.x.ai/v1/stt")!
    private let validationURL = URL(string: "https://api.x.ai/v1/tts/voices")!
    private let apiKeyStorageKey = "XAIAPIKey"
    private let sampleRate = 16_000

    @Published var isAPIKeyValid = false
    @Published var isValidating = false
    @Published var lastValidationError: String?

    private init() {
        isAPIKeyValid = getStoredAPIKey() != nil
    }

    var isConfigured: Bool {
        getStoredAPIKey() != nil
    }

    func getStoredAPIKey() -> String? {
        if let key = UserDefaults.standard.string(forKey: apiKeyStorageKey), !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["XAI_API_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }

    func saveAPIKey(_ key: String) async -> Bool {
        isValidating = true
        lastValidationError = nil
        defer { isValidating = false }

        do {
            let isValid = try await validateAPIKey(key)
            if isValid {
                UserDefaults.standard.set(key, forKey: apiKeyStorageKey)
                isAPIKeyValid = true
                logger.notice("x.ai API key saved and validated successfully")
                return true
            }

            lastValidationError = "x.ai API key validation failed"
            isAPIKeyValid = false
            return false
        } catch {
            lastValidationError = error.localizedDescription
            isAPIKeyValid = false
            logger.error("x.ai API key validation error: \(error.localizedDescription)")
            return false
        }
    }

    func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: apiKeyStorageKey)
        isAPIKeyValid = false
        lastValidationError = nil
        logger.notice("x.ai API key cleared")
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: validationURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAITranscriptionError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return true
            case 401:
                throw XAITranscriptionError.invalidAPIKey
            default:
                throw XAITranscriptionError.requestFailed("HTTP \(httpResponse.statusCode)")
            }
        } catch let error as XAITranscriptionError {
            throw error
        } catch {
            throw XAITranscriptionError.networkError(error)
        }
    }

    func testConnection() async -> (success: Bool, message: String) {
        guard let key = getStoredAPIKey() else {
            return (false, XAITranscriptionError.noAPIKey.localizedDescription)
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
            throw XAITranscriptionError.emptyAudio
        }
        guard let apiKey = getStoredAPIKey() else {
            throw XAITranscriptionError.noAPIKey
        }

        let wavData = Self.wavData(from: audioSamples, sampleRate: sampleRate)
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            fields: [
                ("format", "true"),
                ("language", "en")
            ],
            fileFieldName: "file",
            fileName: "dictation.wav",
            mimeType: "audio/wav",
            fileData: wavData
        )

        var request = URLRequest(url: sttURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAITranscriptionError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw XAITranscriptionError.invalidAPIKey
                }

                let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw XAITranscriptionError.requestFailed("HTTP \(httpResponse.statusCode): \(message)")
            }

            let transcriptionResponse = try JSONDecoder().decode(XAITranscriptionResponse.self, from: data)
            let text = transcriptionResponse.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw XAITranscriptionError.emptyResponse
            }

            logger.notice("x.ai transcription complete: \(text.count) chars")
            return text
        } catch let error as XAITranscriptionError {
            throw error
        } catch let error as DecodingError {
            logger.error("Failed to decode x.ai response: \(String(describing: error))")
            throw XAITranscriptionError.invalidResponse
        } catch {
            throw XAITranscriptionError.networkError(error)
        }
    }

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

private struct XAITranscriptionResponse: Decodable {
    let text: String
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
