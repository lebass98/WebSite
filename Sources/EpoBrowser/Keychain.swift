import Foundation
import Security

/// 로그인 아이디·비밀번호를 macOS 키체인에 보관
enum Keychain {
    private static let service = "com.local.EpoBrowser.login"

    static func save(username: String, password: String) {
        delete()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { DebugLog.write("키체인 저장 실패: \(status)") }
    }

    static func load() -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let dict = result as? [String: Any],
              let user = dict[kSecAttrAccount as String] as? String,
              let data = dict[kSecValueData as String] as? Data,
              let pass = String(data: data, encoding: .utf8)
        else {
            if status != errSecItemNotFound { DebugLog.write("키체인 읽기 실패: \(status)") }
            return nil
        }
        return (user, pass)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
