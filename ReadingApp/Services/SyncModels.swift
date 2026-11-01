import Foundation

/// P4.2 书籍 DTO：跨设备以 `sourceID + title` 为稳定键（本地书 sourceID 为空）。
struct BookDTO: Codable, Equatable, Sendable {
    var sourceID: String?
    var title: String
    var author: String
    var type: String            // novel / comic
    var progress: Double
    var updatedAt: Date
    var coverURL: String?
    var format: String?
    var pageCount: Int?
    var bookURL: String?

    var syncKey: String { "\(sourceID ?? "local")::\(title)" }
}

/// P4.2 书源 DTO（全字段序列化，含漫画专属字段）。
struct SourceDTO: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var type: String
    var enabled: Bool
    var priority: Int
    var searchUrl: String
    var ruleSearch: String
    var ruleBookInfo: String
    var ruleToc: String
    var ruleContent: String
    var imageListRule: String?
    var imageUrlRule: String?
    var nextPageRule: String?
    var adPageFilter: String?
    var updatedAt: Date
}

/// P4.2 设置 DTO（统一 AppSettings，小说/漫画共用）。
struct SettingsDTO: Codable, Equatable, Sendable {
    var syncMode: String
    var fullFileSyncEnabled: Bool
    var defaultTheme: String
    var readerDirection: String
    var fontSize: Double
    var lineSpacing: Double
    var pageTurnMode: String
    var comicReaderMode: String
    var comicBrightness: Double
    var comicEnhanceOn: Bool
    var updatedAt: Date
}

/// P4.2 同步快照（单文件 JSON，存于 WebDAV 远端）。
struct SyncSnapshot: Codable, Equatable, Sendable {
    var version: Int
    var updatedAt: Date
    var deviceID: String
    var books: [BookDTO]
    var sources: [SourceDTO]
    var settings: SettingsDTO?

    static let empty = SyncSnapshot(version: 0, updatedAt: .distantPast, deviceID: "",
                                    books: [], sources: [], settings: nil)
}

extension SyncSnapshot {
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// P4.2 冲突合并：按 key 取 `updatedAt` 较新者（最后写入胜出）；版本号取较大者 +1。
enum SyncMerge {
    static func merge(local: SyncSnapshot, remote: SyncSnapshot) -> SyncSnapshot {
        let books = mergeBooks(local.books, remote.books)
        let sources = mergeSources(local.sources, remote.sources)
        let settings = newerSettings(local.settings, remote.settings)
        let version = max(local.version, remote.version) + 1
        let candidates = [local.updatedAt, remote.updatedAt, settings?.updatedAt].compactMap { $0 }
        let updatedAt = candidates.max() ?? .now
        return SyncSnapshot(
            version: version,
            updatedAt: updatedAt,
            deviceID: local.deviceID.isEmpty ? remote.deviceID : local.deviceID,
            books: books,
            sources: sources,
            settings: settings
        )
    }

    static func mergeBooks(_ a: [BookDTO], _ b: [BookDTO]) -> [BookDTO] {
        var map: [String: BookDTO] = [:]
        for item in a + b {
            if let existing = map[item.syncKey] {
                map[item.syncKey] = item.updatedAt >= existing.updatedAt ? item : existing
            } else {
                map[item.syncKey] = item
            }
        }
        return map.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func mergeSources(_ a: [SourceDTO], _ b: [SourceDTO]) -> [SourceDTO] {
        var map: [String: SourceDTO] = [:]
        for item in a + b {
            if let existing = map[item.id] {
                map[item.id] = item.updatedAt >= existing.updatedAt ? item : existing
            } else {
                map[item.id] = item
            }
        }
        return map.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func newerSettings(_ a: SettingsDTO?, _ b: SettingsDTO?) -> SettingsDTO? {
        switch (a, b) {
        case let (a?, b?): return a.updatedAt >= b.updatedAt ? a : b
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }
}

/// P4.2 同步结果。
struct SyncResult: Equatable, Sendable {
    var remoteWasEmpty: Bool
    var bookCount: Int
    var sourceCount: Int
    var version: Int
    var syncedAt: Date
}
