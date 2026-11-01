import Foundation
import SwiftData

/// P4.4 快照构建/应用：在 SwiftData 与 `SyncSnapshot` 之间转换。
@MainActor
enum SyncSnapshotBuilder {

    /// 读取本地库构建快照（version 由同步流程决定，此处置 0）。
    static func build(context: ModelContext, deviceID: String) throws -> SyncSnapshot {
        let books = try context.fetch(FetchDescriptor<Book>())
        let sources = try context.fetch(FetchDescriptor<SourceRule>())
        let settings = try AppSettings.loadOrCreate(in: context)

        let bookDTOs = books.map { b in
            BookDTO(sourceID: b.sourceID, title: b.title, author: b.author,
                    type: b.type.rawValue, progress: b.progress, updatedAt: b.updatedAt,
                    coverURL: b.coverURL, format: b.format, pageCount: b.pageCount, bookURL: b.bookURL)
        }
        let sourceDTOs = sources.map { s in
            SourceDTO(id: s.id, name: s.name, type: s.type.rawValue, enabled: s.enabled,
                      priority: s.priority, searchUrl: s.searchUrl, ruleSearch: s.ruleSearch,
                      ruleBookInfo: s.ruleBookInfo, ruleToc: s.ruleToc, ruleContent: s.ruleContent,
                      imageListRule: s.imageListRule, imageUrlRule: s.imageUrlRule,
                      nextPageRule: s.nextPageRule, adPageFilter: s.adPageFilter, updatedAt: s.updatedAt)
        }
        let settingsDTO = SettingsDTO(
            syncMode: settings.syncMode.rawValue,
            fullFileSyncEnabled: settings.fullFileSyncEnabled,
            defaultTheme: settings.defaultTheme,
            readerDirection: settings.readerDirection,
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            pageTurnMode: settings.pageTurnMode,
            comicReaderMode: settings.comicReaderMode,
            comicBrightness: settings.comicBrightness,
            comicEnhanceOn: settings.comicEnhanceOn,
            updatedAt: .now
        )
        return SyncSnapshot(version: 0, updatedAt: .now, deviceID: deviceID,
                            books: bookDTOs, sources: sourceDTOs, settings: settingsDTO)
    }

    /// 将（已合并的）快照写回本地库：书籍按 syncKey、书源按 id upsert；设置写单例。
    static func apply(_ snapshot: SyncSnapshot, context: ModelContext) throws {
        // 书籍：以 sourceID+title 为键
        let existingBooks = try context.fetch(FetchDescriptor<Book>())
        var bookIndex: [String: Book] = [:]
        for b in existingBooks { bookIndex["\(b.sourceID ?? "local")::\(b.title)"] = b }

        for dto in snapshot.books {
            let type = ContentType(rawValue: dto.type) ?? .novel
            if let book = bookIndex[dto.syncKey] {
                book.author = dto.author
                book.type = type
                book.coverURL = dto.coverURL
                book.progress = min(max(dto.progress, 0), 1)
                book.updatedAt = dto.updatedAt
                book.format = dto.format
                book.pageCount = dto.pageCount
                book.bookURL = dto.bookURL
            } else {
                let book = Book(title: dto.title, author: dto.author, type: type,
                                sourceID: dto.sourceID, coverURL: dto.coverURL,
                                updatedAt: dto.updatedAt, progress: dto.progress,
                                format: dto.format, pageCount: dto.pageCount, bookURL: dto.bookURL)
                context.insert(book)
            }
        }

        // 书源：以 id 为键
        let existingSources = try context.fetch(FetchDescriptor<SourceRule>())
        var sourceIndex: [String: SourceRule] = [:]
        for s in existingSources { sourceIndex[s.id] = s }

        for dto in snapshot.sources {
            let type = ContentType(rawValue: dto.type) ?? .novel
            if let source = sourceIndex[dto.id] {
                source.name = dto.name
                source.type = type
                source.enabled = dto.enabled
                source.priority = dto.priority
                source.searchUrl = dto.searchUrl
                source.ruleSearch = dto.ruleSearch
                source.ruleBookInfo = dto.ruleBookInfo
                source.ruleToc = dto.ruleToc
                source.ruleContent = dto.ruleContent
                source.imageListRule = dto.imageListRule
                source.imageUrlRule = dto.imageUrlRule
                source.nextPageRule = dto.nextPageRule
                source.adPageFilter = dto.adPageFilter
                source.updatedAt = dto.updatedAt
            } else {
                let source = SourceRule(
                    id: dto.id, name: dto.name, type: type, enabled: dto.enabled,
                    priority: dto.priority, searchUrl: dto.searchUrl, ruleSearch: dto.ruleSearch,
                    ruleBookInfo: dto.ruleBookInfo, ruleToc: dto.ruleToc, ruleContent: dto.ruleContent,
                    imageListRule: dto.imageListRule, imageUrlRule: dto.imageUrlRule,
                    nextPageRule: dto.nextPageRule, adPageFilter: dto.adPageFilter,
                    updatedAt: dto.updatedAt
                )
                context.insert(source)
            }
        }

        // 设置
        if let sd = snapshot.settings {
            let settings = try AppSettings.loadOrCreate(in: context)
            settings.syncMode = SyncMode(rawValue: sd.syncMode) ?? .metadata
            settings.fullFileSyncEnabled = sd.fullFileSyncEnabled
            settings.defaultTheme = sd.defaultTheme
            settings.readerDirection = sd.readerDirection
            settings.fontSize = sd.fontSize
            settings.lineSpacing = sd.lineSpacing
            settings.pageTurnMode = sd.pageTurnMode
            settings.comicReaderMode = sd.comicReaderMode
            settings.comicBrightness = sd.comicBrightness
            settings.comicEnhanceOn = sd.comicEnhanceOn
        }

        try context.save()
    }
}

/// P4.4 WebDAV 同步服务：拉取 → 合并（LWW）→ 应用 → 上传 → 本地双写备份。
@MainActor
final class SyncService {
    private let context: ModelContext
    private let config: SyncConfig
    private let credentials: CredentialStoring
    private let makeClient: (WebDAVConfig, String) -> WebDAVServicing
    private let backupDirectory: URL?
    let remoteFileName: String

    init(context: ModelContext,
         config: SyncConfig,
         credentials: CredentialStoring,
         remoteFileName: String = "readingapp-sync.json",
         backupDirectory: URL? = nil,
         makeClient: @escaping (WebDAVConfig, String) -> WebDAVServicing = { cfg, pwd in
             WebDAVClient(config: cfg, password: pwd)
         }) {
        self.context = context
        self.config = config
        self.credentials = credentials
        self.remoteFileName = remoteFileName
        self.backupDirectory = backupDirectory
        self.makeClient = makeClient
    }

    private var webdavConfig: WebDAVConfig {
        WebDAVConfig(baseURL: config.serverURL, username: config.username, directory: config.remoteDirectory)
    }

    private func client() -> WebDAVServicing {
        makeClient(webdavConfig, credentials.password(for: config.username) ?? "")
    }

    func testConnection() async throws {
        try await client().testConnection()
    }

    /// 立即同步，返回合并结果。
    func syncNow() async throws -> SyncResult {
        let client = self.client()
        let local = try SyncSnapshotBuilder.build(context: context, deviceID: config.deviceID)
        let remoteData = try await client.download(path: remoteFileName)

        let result: SyncSnapshot
        let remoteWasEmpty: Bool
        if let remoteData, let remote = try? SyncSnapshot.makeDecoder().decode(SyncSnapshot.self, from: remoteData) {
            result = SyncMerge.merge(local: local, remote: remote)
            remoteWasEmpty = false
        } else {
            var first = local
            first.version = local.version + 1
            first.updatedAt = .now
            result = first
            remoteWasEmpty = true
        }

        try SyncSnapshotBuilder.apply(result, context: context)

        let payload = try SyncSnapshot.makeEncoder().encode(result)
        try await client.upload(path: remoteFileName, data: payload)
        try? backup(payload)

        config.lastSyncAt = .now
        config.lastSyncVersion = result.version
        try? context.save()

        return SyncResult(remoteWasEmpty: remoteWasEmpty,
                          bookCount: result.books.count,
                          sourceCount: result.sources.count,
                          version: result.version,
                          syncedAt: .now)
    }

    /// 关键数据双写备份（best-effort，失败不阻断同步）。
    private func backup(_ data: Data) throws {
        let dir = backupDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Library/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        try data.write(to: dir.appendingPathComponent("sync-\(stamp).json"))
    }
}
