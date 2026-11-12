import Foundation
import Security

/// Minimal generic-password wrapper. API keys live here and nowhere else (never in defaults, files or URLs).
enum Keychain {
    private static let service = "com.harrisonmartel.claude-avatar"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Values already read (or just saved) this run, so macOS asks for Keychain access at most once per launch.
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        var ok = status == errSecSuccess
        if !ok {
            var add = query(account)
            add[kSecValueData as String] = data
            ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        if ok { lock.lock(); cache[account] = value; lock.unlock() }
        return ok
    }

    static func get(_ account: String) -> String? {
        lock.lock(); let hit = cache[account]; lock.unlock()
        if let hit { return hit }
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        lock.lock(); cache[account] = value; lock.unlock()
        return value
    }

    /// Existence check that reads only attributes, never the secret, so it never triggers a prompt.
    static func has(_ account: String) -> Bool {
        lock.lock(); let cached = cache[account] != nil; lock.unlock()
        if cached { return true }
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        lock.lock(); cache[account] = nil; lock.unlock()
        SecItemDelete(query(account) as CFDictionary)
    }
}
