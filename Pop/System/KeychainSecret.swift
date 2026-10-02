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

    /// 读的结果：没存过和读不出来（钥匙串锁着、没允许）要分开处理
    enum ReadResult: Equatable {
        case value(String)
        case notFound
        case failed(OSStatus)
    }

    func read() -> String? {
        if case .value(let text) = readResult() {
            return text
        }
        return nil
    }

    func readResult() -> ReadResult {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return .failed(errSecDecode) }
            return .value(text)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
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

    /// 保存，不先删掉原来的：存不进去时原来的还在（空字符串表示删除）。成功返回 true。
    /// 一项里存着好几个密钥时用这个，免得存失败把原来的都弄丢
    @discardableResult
    func replace(_ value: String) -> Bool {
        guard !value.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: label]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = label
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
