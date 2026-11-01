import Foundation
import SwiftData

/// P3.3 图片页下载抽象（可注入，便于测试替身）。仅在主线程使用。
@MainActor
protocol PageDownloading {
    /// 入队一页图片下载，按 `bookID/chapter/index` 命名，返回本地文件名 key。
    @discardableResult
    func enqueuePage(bookID: String, chapter: String, index: Int, url: String) -> String
    /// 该文件名对应的本地文件 URL（已下载则返回，否则 nil）。
    func localURL(for fileName: String) -> URL?
}

/// P3.3 应用级下载中心：全局唯一的 `DownloadManager`。
///
/// P2 下载中心与 P3 漫画图片页缓存共用同一个管理器，避免多个 `DownloadManager`
/// 争抢同一个 `BackgroundDownloadCoordinator.onEvent`（后者会被最后构造者覆盖，
/// 导致另一方的下载事件丢失、进度停滞）。
@MainActor
enum AppDownloadCenter {
    static let manager: DownloadManager = DownloadManager(
        store: DownloadStore(context: PersistenceController.shared.context),
        runner: BackgroundDownloadCoordinator.shared
    )
}

/// P3.3 基于 P2 `DownloadManager` 的漫画图片页缓存实现。
///
/// 复用 P2 下载底座：每个图片页作为一个下载单元入队（`DownloadManager` 负责并发/续传/落盘），
/// 落盘后由 `FileStoring` 解析本地 URL。阅读器优先读本地缓存，未命中则回退远程 URL。
@MainActor
final class ComicPageCacheService: PageDownloading {
    private let manager: DownloadManager
    private let fileStore: FileStoring

    init(manager: DownloadManager, fileStore: FileStoring) {
        self.manager = manager
        self.fileStore = fileStore
    }

    /// 生产默认实例：复用全局下载中心与 `production` 落盘目录。
    static func production() -> ComicPageCacheService {
        ComicPageCacheService(manager: AppDownloadCenter.manager, fileStore: DownloadFileManager.production)
    }

    /// 本地文件名 key：目录层级用 `/` 表达（落盘时由 `safeFileName` 转义为下划线）。
    func fileName(bookID: String, chapter: String, index: Int) -> String {
        "\(bookID)/\(chapter)/\(index).img"
    }

    func enqueuePage(bookID: String, chapter: String, index: Int, url: String) -> String {
        let name = fileName(bookID: bookID, chapter: chapter, index: index)
        _ = try? manager.enqueue(url: url, fileName: name, bookID: bookID)
        return name
    }

    func localURL(for fileName: String) -> URL? {
        fileStore.exists(fileName: fileName) ? fileStore.destinationURL(for: fileName) : nil
    }
}
