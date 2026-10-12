import Foundation
import Security

enum DeepgramKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.aireaudio.recorder.deepgram",
        kSecAttrAccount as String: "api-key"
    ]

    static func isConfigured() throws -> Bool {
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw failure(status) }
        return true
    }

    static func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw failure(status) }
        return key
    }

    static func save(_ proposed: String) throws {
        let key = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw AppError("Pega únicamente la API key de Deepgram, sin espacios ni el prefijo Token.")
        }
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> AppError {
        AppError("No se pudo acceder al Llavero de macOS (\(status)). Autoriza el acceso a ChaceRecordings si macOS lo solicita.")
    }
}
