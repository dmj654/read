import Foundation
import SwiftData
import Observation

/// P4.6 同步设置 ViewModel：编辑 WebDAV 配置、测试连接、立即同步。
@Observable
@MainActor
final class SyncViewModel {
    enum Status: Equatable {
        case idle
        case testing
        case syncing
        case success(String)
        case failed(String)
    }

    private let context: ModelContext
    private let credentials: CredentialStoring
    private let config: SyncConfig
    private var service: SyncService

    var serverURL: String
    var username: String
    var password: String
    var directory: String
    var autoSync: Bool
    var status: Status = .idle
    var lastSyncAt: Date?
    var lastVersion: Int

    init(context: ModelContext = PersistenceController.shared.context,
         credentials: CredentialStoring = KeychainCredentialStore()) {
        self.context = context
        self.credentials = credentials

        let cfg: SyncConfig
        if let existing = try? SyncConfig.loadOrCreate(in: context) {
            cfg = existing
        } else {
            cfg = SyncConfig()
            context.insert(cfg)
        }
        self.config = cfg
        self.service = SyncService(context: context, config: cfg, credentials: credentials)

        self.serverURL = cfg.serverURL
        self.username = cfg.username
        self.password = credentials.password(for: cfg.username) ?? ""
        self.directory = cfg.remoteDirectory
        self.autoSync = cfg.autoSync
        self.lastSyncAt = cfg.lastSyncAt
        self.lastVersion = cfg.lastSyncVersion
    }

    var isBusy: Bool { status == .testing || status == .syncing }
    var canSubmit: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty }

    /// 落库配置（密码进 Keychain）并重建同步服务。
    func saveConfig() {
        config.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
        config.username = username
        config.remoteDirectory = directory.isEmpty ? "ReadingApp" : directory
        config.autoSync = autoSync
        try? credentials.setPassword(password, for: config.username)
        try? context.save()
        service = SyncService(context: context, config: config, credentials: credentials)
    }

    func testConnection() async {
        saveConfig()
        status = .testing
        do {
            try await service.testConnection()
            status = .success("连接成功")
        } catch {
            status = .failed(message(error))
        }
    }

    func syncNow() async {
        saveConfig()
        status = .syncing
        do {
            let result = try await service.syncNow()
            lastSyncAt = config.lastSyncAt
            lastVersion = config.lastSyncVersion
            status = .success("同步完成 · v\(result.version) · \(result.bookCount) 本 / \(result.sourceCount) 源")
        } catch {
            status = .failed(message(error))
        }
    }

    private func message(_ error: Error) -> String {
        guard let e = error as? WebDAVError else { return error.localizedDescription }
        switch e {
        case .unauthorized: return "鉴权失败，请检查账号/密码"
        case .invalidURL: return "服务器地址无效"
        case .notFound: return "远端路径不存在"
        case .badStatus(let code): return "服务器返回 \(code)"
        case .parse: return "响应解析失败"
        }
    }
}
