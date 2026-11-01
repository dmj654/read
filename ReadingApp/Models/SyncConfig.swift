import Foundation
import SwiftData

/// P4.4 WebDAV 同步配置（单例式）。密码仅存 Keychain（`CredentialStoring`），不入库、不同步。
@Model
final class SyncConfig {
    static let singletonID = "sync-config"

    @Attribute(.unique) var id: String
    var serverURL: String
    var username: String
    var remoteDirectory: String
    var autoSync: Bool
    var lastSyncAt: Date?
    var lastSyncVersion: Int
    var deviceID: String

    init(
        id: String = SyncConfig.singletonID,
        serverURL: String = "",
        username: String = "",
        remoteDirectory: String = "ReadingApp",
        autoSync: Bool = false,
        lastSyncAt: Date? = nil,
        lastSyncVersion: Int = 0,
        deviceID: String = UUID().uuidString
    ) {
        self.id = id
        self.serverURL = serverURL
        self.username = username
        self.remoteDirectory = remoteDirectory
        self.autoSync = autoSync
        self.lastSyncAt = lastSyncAt
        self.lastSyncVersion = lastSyncVersion
        self.deviceID = deviceID
    }

    /// 取用全局唯一配置；不存在则按默认值创建。
    static func loadOrCreate(in context: ModelContext) throws -> SyncConfig {
        // 同 AppSettings：`#Predicate` 不能引用静态成员，先取局部常量。
        let singletonID = SyncConfig.singletonID
        let descriptor = FetchDescriptor<SyncConfig>(
            predicate: #Predicate { $0.id == singletonID }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let config = SyncConfig()
        context.insert(config)
        try context.save()
        return config
    }
}
