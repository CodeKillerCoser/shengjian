import Foundation
import Security

final class CredentialStore {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.rimevoice.api",
        kSecAttrAccount as String: "default",
    ]
    struct ReadResult {
        let value: String
        let status: OSStatus
    }
    private static let lock = NSRecursiveLock()
    private static var cached: String?
    // Legacy login-keychain queries do not consistently honor kSecUseAuthenticationUI.
    // Serialize our keychain calls and explicitly forbid UI for background reads.
    private static func silent<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        var allowed: DarwinBoolean = false
        SecKeychainGetUserInteractionAllowed(&allowed)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return operation()
    }
    static func containsKey() -> Bool {
        silent {
            var q = query
            q[kSecReturnAttributes as String] = true
            return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
        }
    }
    static func load() -> ReadResult {
        silent {
            if let cached { return ReadResult(value: cached, status: errSecSuccess) }
            var q = query
            q[kSecReturnData as String] = true
            q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var result: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &result)
            let value = (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if status == errSecSuccess || status == errSecItemNotFound { cached = value }
            return ReadResult(value: value, status: status)
        }
    }
    static func keyForModelRequest() throws -> String {
        let saved = load()
        guard saved.status == errSecSuccess || saved.status == errSecItemNotFound else {
            throw failure("已保存的 API Key 无法静默读取，请在设置中重新填写并保存一次（\(saved.status)）")
        }
        return saved.value
    }
    static func save(_ value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure("钥匙串删除失败：\(status)") }
            cached = nil
            return
        }
        // Bind this item's access to the current executable's stable signed
        // requirement. Explicit saving also migrates legacy ad-hoc item ACLs.
        var trusted: SecTrustedApplication?
        var status = SecTrustedApplicationCreateFromPath(nil, &trusted)
        guard status == errSecSuccess, let trusted else { throw failure("无法创建钥匙串访问身份：\(status)") }
        var access: SecAccess?
        status = SecAccessCreate("声笺 API Key" as CFString, [trusted] as CFArray, &access)
        guard status == errSecSuccess, let access else { throw failure("无法创建钥匙串访问规则：\(status)") }
        // Limit silent decryption to this trusted app; do not require a password
        // again on every decrypt operation for a key the user explicitly saved.
        let decryptACLs = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) as! [SecACL]
        for acl in decryptACLs {
            status = SecACLSetContents(acl, [trusted] as CFArray, "声笺 API Key" as CFString, [])
            guard status == errSecSuccess else { throw failure("无法设置密钥访问规则：\(status)") }
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccess as String: access]
        status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            for (key, value) in attributes { q[key] = value }
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure("钥匙串保存失败：\(status)") }
        cached = value
    }
}
