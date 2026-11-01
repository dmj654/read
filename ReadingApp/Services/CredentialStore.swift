import Foundation
import Security

/// P4.3 凭据存储抽象：WebDAV 密码只进 Keychain，绝不写入 SwiftData / 同步文件。
protocol CredentialStoring {
    func password(for account: String) -> String?
    func setPassword(_ password: String, for account: String) throws
    func deletePassword(for account: String)
}

enum CredentialError: Error, Equatable {
    case keychain(OSStatus)
}

/// P4.3 Keychain 实现（通用密码项，service + account 定位）。
final class KeychainCredentialStore: CredentialStoring {
    private let service: String

    init(service: String = "com.example.ReadingApp.webdav") {
        self.service = service
    }

    func password(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String, for account: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { throw CredentialError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw CredentialError.keychain(status)
        }
    }

    func deletePassword(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// P4.3 内存实现（单元测试 / 无 Keychain 环境）。
final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    func password(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[account]
    }

    func setPassword(_ password: String, for account: String) throws {
        lock.lock(); store[account] = password; lock.unlock()
    }

    func deletePassword(for account: String) {
        lock.lock(); store.removeValue(forKey: account); lock.unlock()
    }
}
