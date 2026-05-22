import Foundation
import Security

protocol APIKeyStore: AnyObject {
    func loadOpenAIAPIKey() throws -> String?
    func saveOpenAIAPIKey(_ key: String) throws
    func deleteOpenAIAPIKey() throws
    func ensureDeviceToken() throws -> String
}

enum APIKeyStoreError: LocalizedError, Equatable {
    case emptyKey
    case invalidKeyData
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "Service token cannot be empty."
        case .invalidKeyData:
            "Saved service token could not be read."
        case .keychainFailure:
            "Could not update the saved service token."
        }
    }
}

final class KeychainAPIKeyStore: APIKeyStore {
    private let service: String
    private let account = "lifeorganize_device_token"

    init(service: String = Bundle.main.bundleIdentifier ?? "LifeOrganize") {
        self.service = service
    }

    func loadOpenAIAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(status)
        }
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.invalidKeyData
        }
        return key
    }

    func saveOpenAIAPIKey(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw APIKeyStoreError.emptyKey
        }

        let data = Data(normalized.utf8)
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        if addStatus != errSecDuplicateItem {
            throw APIKeyStoreError.keychainFailure(addStatus)
        }

        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(updateStatus)
        }
    }

    func deleteOpenAIAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainFailure(status)
        }
    }

    func ensureDeviceToken() throws -> String {
        if let existing = try loadOpenAIAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString + "." + UUID().uuidString
        try saveOpenAIAPIKey(token)
        return token
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

final class InMemoryAPIKeyStore: APIKeyStore {
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func loadOpenAIAPIKey() throws -> String? {
        key
    }

    func saveOpenAIAPIKey(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw APIKeyStoreError.emptyKey
        }
        self.key = normalized
    }

    func deleteOpenAIAPIKey() throws {
        key = nil
    }

    func ensureDeviceToken() throws -> String {
        if let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        let token = UUID().uuidString + "." + UUID().uuidString
        key = token
        return token
    }
}
