import Foundation
import Security

final class APIKeyStorageService {
    static let shared = APIKeyStorageService()

    private let service = "com.hiq.ParaDict.api-keys"

    private init() {}

    func loadKey(for account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw StorageError(status: status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            throw StorageError.invalidData
        }
        return key
    }

    func saveKey(_ key: String, for account: String) throws {
        let lookup: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(key.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw StorageError(status: updateStatus)
        }

        var newItem = lookup
        attributes.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StorageError(status: addStatus)
        }
    }

    func deleteKey(for account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError(status: status)
        }
    }

    enum StorageError: LocalizedError {
        case keychain(OSStatus)
        case invalidData

        init(status: OSStatus) {
            self = .keychain(status)
        }

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
                return "Keychain error \(status): \(message)"
            case .invalidData:
                return "The stored API key is not valid UTF-8 data."
            }
        }
    }
}
