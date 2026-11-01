import Foundation

/// 内容类型：小说 / 漫画。
/// P0.3 起将基于它扩展 SwiftData @Model 的 SourceRule / Book 等实体。
enum ContentType: String, Codable, Sendable {
    case novel
    case comic
}

import SwiftData

/// 书源 / 漫源统一数据模型（同源规则体系）。
/// 漫画专属字段在 P3 落地解析逻辑，此处先以可选 String 占位，
/// 后续扩展字段不应破坏 SwiftData 轻量迁移。
@Model
final class SourceRule {
    @Attribute(.unique) var id: String
    var name: String
    var type: ContentType          // .novel / .comic
    var enabled: Bool
    var priority: Int

    // 通用规则（Legado 风格）
    var searchUrl: String
    var ruleSearch: String
    var ruleBookInfo: String
    var ruleToc: String
    var ruleContent: String

    // 漫画专属（占位，P3 细化）
    var imageListRule: String?
    var imageUrlRule: String?
    var nextPageRule: String?
    var adPageFilter: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        type: ContentType = .novel,
        enabled: Bool = true,
        priority: Int = 0,
        searchUrl: String = "",
        ruleSearch: String = "",
        ruleBookInfo: String = "",
        ruleToc: String = "",
        ruleContent: String = "",
        imageListRule: String? = nil,
        imageUrlRule: String? = nil,
        nextPageRule: String? = nil,
        adPageFilter: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.priority = priority
        self.searchUrl = searchUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.imageListRule = imageListRule
        self.imageUrlRule = imageUrlRule
        self.nextPageRule = nextPageRule
        self.adPageFilter = adPageFilter
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 同步范围：仅元数据（默认）/ 全量（含文件，可选开关）。
/// Codable 以便后续 P4 WebDAV 序列化传输。
enum SyncMode: String, Codable, Sendable {
    case metadata
    case full
}

/// 全局设置实体（单例式：固定 id）。
/// 落实同步策略决策：默认仅元数据，全量文件同步为可选开关（默认关闭）。
@Model
final class AppSettings {
    static let singletonID = "app-settings"

    @Attribute(.unique) var id: String
    var syncMode: SyncMode
    var fullFileSyncEnabled: Bool

    // 通用 / 阅读器偏好占位（P5 细化）
    var defaultTheme: String
    var readerDirection: String

    // P1 小说阅读器偏好（默认基线）
    var fontSize: Double           // 正文字号 pt
    var lineSpacing: Double         // 行距倍数
    var pageTurnMode: String        // curl / slide / scroll

    // P3 漫画阅读器偏好
    var comicReaderMode: String     // single / double / webtoon
    var comicBrightness: Double     // 亮度倍率（0.2...1.5）
    var comicEnhanceOn: Bool        // 图像增强（对比度提升）

    init(
        id: String = AppSettings.singletonID,
        syncMode: SyncMode = .metadata,
        fullFileSyncEnabled: Bool = false,
        defaultTheme: String = "auto",
        readerDirection: String = "rtl",
        fontSize: Double = 17,
        lineSpacing: Double = 1.5,
        pageTurnMode: String = "curl",
        comicReaderMode: String = "single",
        comicBrightness: Double = 1,
        comicEnhanceOn: Bool = false
    ) {
        self.id = id
        self.syncMode = syncMode
        self.fullFileSyncEnabled = fullFileSyncEnabled
        self.defaultTheme = defaultTheme
        self.readerDirection = readerDirection
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.pageTurnMode = pageTurnMode
        self.comicReaderMode = comicReaderMode
        self.comicBrightness = comicBrightness
        self.comicEnhanceOn = comicEnhanceOn
    }

    /// 取用全局唯一设置记录；不存在则按默认值创建。
    static func loadOrCreate(in context: ModelContext) throws -> AppSettings {
        // `#Predicate` 宏展开成 key path 表达式，不能直接引用静态成员
        // （error: key path cannot refer to static member 'singletonID'），
        // 必须先落到局部常量再被闭包捕获。
        let singletonID = AppSettings.singletonID
        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate { $0.id == singletonID }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}

/// 书架统一实体：小说与漫画共用基础契约（stub 版本）。
/// 漫画专属字段在 P3 细化，此处以可选类型预留占位。
@Model
final class Book {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    var type: ContentType          // .novel / .comic
    var sourceID: String?          // 关联 SourceRule.id（本地书为 nil）
    var coverURL: String?
    var updatedAt: Date
    var progress: Double           // 0...1

    // 漫画专属占位（P3 细化）
    var format: String?            // cbz / pdf / images
    var pageCount: Int?

    // P4 双体系收口：书架打开在线书需记录详情页 URL
    var bookURL: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        author: String = "",
        type: ContentType = .novel,
        sourceID: String? = nil,
        coverURL: String? = nil,
        updatedAt: Date = .now,
        progress: Double = 0,
        format: String? = nil,
        pageCount: Int? = nil,
        bookURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.type = type
        self.sourceID = sourceID
        self.coverURL = coverURL
        self.updatedAt = updatedAt
        self.progress = progress
        self.format = format
        self.pageCount = pageCount
        self.bookURL = bookURL
    }
}
