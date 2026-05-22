import Foundation
import Security

protocol DeviceTokenStore: AnyObject {
    func loadDeviceToken() throws -> String?
    func saveDeviceToken(_ token: String) throws
    func deleteDeviceToken() throws
    func ensureDeviceToken() throws -> String
}

enum DeviceTokenStoreError: LocalizedError, Equatable {
    case emptyToken
    case invalidTokenData
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyToken:
            "Service token cannot be empty."
        case .invalidTokenData:
            "Saved service token could not be read."
        case .keychainFailure:
            "Could not update the saved service token."
        }
    }
}

final class KeychainDeviceTokenStore: DeviceTokenStore {
    private let service: String
    private let account = "lifeorganize_device_token"

    init(service: String = Bundle.main.bundleIdentifier ?? "LifeOrganize") {
        self.service = service
    }

    func loadDeviceToken() throws -> String? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw DeviceTokenStoreError.keychainFailure(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw DeviceTokenStoreError.invalidTokenData
        }
        return token
    }

    func saveDeviceToken(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw DeviceTokenStoreError.emptyToken
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
            throw DeviceTokenStoreError.keychainFailure(addStatus)
        }

        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw DeviceTokenStoreError.keychainFailure(updateStatus)
        }
    }

    func deleteDeviceToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeviceTokenStoreError.keychainFailure(status)
        }
    }

    func ensureDeviceToken() throws -> String {
        if let existing = try loadDeviceToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let token = UUID().uuidString + "." + UUID().uuidString
        try saveDeviceToken(token)
        return token
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class InMemoryDeviceTokenStore: DeviceTokenStore {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadDeviceToken() throws -> String? {
        token
    }

    func saveDeviceToken(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw DeviceTokenStoreError.emptyToken
        }
        self.token = normalized
    }

    func deleteDeviceToken() throws {
        token = nil
    }

    func ensureDeviceToken() throws -> String {
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token
        }
        let generatedToken = UUID().uuidString + "." + UUID().uuidString
        token = generatedToken
        return generatedToken
    }
}
