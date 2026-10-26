import Foundation
import Security

enum APIKeyName: String, CaseIterable, Identifiable {
    case yandexGeocoder = "YANDEX_GEOCODER_API_KEY"
    case dadata = "DADATA_API_KEY"
    case dadataSecret = "DADATA_SECRET_KEY"

    var id: String { rawValue }

    var title: String {
        rawValue
    }

    var helpText: String {
        switch self {
        case .yandexGeocoder:
            return "Ключ API Яндекс Геокодера."
        case .dadata:
            return "Токен DaData с доступом к очистке адресов."
        case .dadataSecret:
            return "Секретный ключ DaData."
        }
    }
}

enum APIKeyStore {
    private static let service = Bundle.main.bundleIdentifier ?? "ColorMap.APIKeys"

    static func load(_ key: APIKeyName) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return value
    }

    static func save(_ value: String, for key: APIKeyName) throws {
        let accountQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            let status = SecItemDelete(accountQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw APIKeyStoreError.keychain(status)
            }
            return
        }

        let data = Data(trimmedValue.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(
            accountQuery as CFDictionary,
            updateAttributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }

        var addQuery = accountQuery
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }
}

private enum APIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Не удалось сохранить ключ в Keychain (код \(status))."
        }
    }
}
