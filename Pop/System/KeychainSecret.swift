import Foundation
import Security

/// 存在这台 Mac 钥匙串里的一段密钥（API Key 之类），不跟设置一起同步。
struct KeychainSecret {
    let service: String
    let account: String
    /// 「钥匙串访问」里显示的名字
    let label: String

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 存过没有。只查有没有这一项、不读内容，不会弹出钥匙串的授权框
    var exists: Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// 保存（空字符串表示删除）。成功返回 true。
    @discardableResult
    func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrLabel as String] = label
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
