import Foundation
import SwiftData
import Observation

/// P3.4 漫画阅读模式。
enum ComicReaderMode: String, CaseIterable, Sendable {
    case single   // 单页
    case `double` // 双页（并排两页）
    case webtoon  // 卷轴长图（竖向无限滚动）
}

/// P3.4 阅读器加载来源。
enum ComicLoadSource {
    /// 本地 CBZ / PDF 容器；`adFilter` 对页名做广告页过滤（nil 不过滤）。
    case local(ComicContainer, adFilter: String?)
    /// 在线漫画：书源 + 章节 URL + 缓存下载器（可空）+ 漫源服务（可注入以便测试）。
    case online(source: SourceRule, chapterURL: String,
                downloader: PageDownloading?, service: ComicSourceService)
}

/// P3.4 漫画阅读器 ViewModel（主线程 Actor + Observation）。
///
/// 职责：加载页列表（本地容器或在线抓取）→ 广告过滤 → 翻页/跳转（自动跳过广告页）
/// → 进度持久化到 `Book.progress`；提供在线页的本地缓存解析。
@Observable
@MainActor
final class ComicReaderViewModel {
    private let loadSource: ComicLoadSource
    private let book: Book?

    var mode: ComicReaderMode
    var scale: CGFloat = 1
    var brightness: Double
    var enhanceOn: Bool

    private var container: ComicContainer?
    private(set) var pages: [ComicImagePage] = []   // 经广告过滤后的有效页
    var currentIndex = 0                            // 可写：供 TabView selection 绑定
    var isLoading = false
    var errorMessage: String?

    init(loadSource: ComicLoadSource, book: Book? = nil,
         mode: ComicReaderMode = .single, brightness: Double = 1, enhanceOn: Bool = false) {
        self.loadSource = loadSource
        self.book = book
        self.mode = mode
        self.brightness = brightness
        self.enhanceOn = enhanceOn
    }

    // MARK: 派生状态

    var pageCount: Int { pages.count }
    var currentPage: ComicImagePage? { pages.isEmpty ? nil : pages[currentIndex] }
    var canGoNext: Bool { currentIndex + 1 < pages.count }
    var canGoPrev: Bool { currentIndex > 0 }

    /// 来源类型（供视图选择本地位图渲染 / 在线 URL 渲染）。
    var isLocal: Bool { if case .local = loadSource { return true }; return false }
    var isOnline: Bool { if case .online = loadSource { return true }; return false }

    // MARK: 加载

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch loadSource {
            case .local(let container, let adFilter):
                self.container = container
                var ps: [ComicImagePage] = []
                for i in 0..<container.pageCount {
                    let name = container.pageName(at: i)
                    ps.append(ComicImagePage(index: i, imageURL: name,
                                             isAd: ComicAdFilter.isAd(name, rule: adFilter)))
                }
                pages = ps.filter { !$0.isAd }
            case .online(let source, let chapterURL, let downloader, let service):
                // 在线广告过滤由 ComicSourceService 依 source.adPageFilter 完成。
                let fetched = try await service.fetchImagePages(chapterURL: chapterURL, source: source)
                pages = fetched
                if let downloader {
                    let bid = book?.id ?? "unknown"
                    for p in fetched {
                        _ = downloader.enqueuePage(bookID: bid, chapter: chapterURL, index: p.index, url: p.imageURL)
                    }
                }
            }
            restoreProgress()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 导航（广告页已在 pages 中剔除，故相邻页即有效页）

    func next() {
        guard canGoNext else { return }
        currentIndex += 1
        persistProgress()
    }

    func prev() {
        guard canGoPrev else { return }
        currentIndex -= 1
        persistProgress()
    }

    func goTo(_ index: Int) {
        guard (0..<pages.count).contains(index) else { return }
        currentIndex = index
        persistProgress()
    }

    // MARK: 取图

    /// 本地容器：直接返回位图数据。
    func localPageData(at index: Int) -> Data? {
        guard case .local(let c, _) = loadSource, (0..<c.pageCount).contains(index) else { return nil }
        return try? c.pageData(at: index)
    }

    /// 在线页：优先本地缓存，否则回退远程 URL。
    func resolvedURL(for page: ComicImagePage, downloader: PageDownloading?) -> URL? {
        if let downloader, let local = downloader.localURL(for: fileName(for: page)) {
            return local
        }
        return URL(string: page.imageURL)
    }

    // MARK: 内部

    private func fileName(for page: ComicImagePage) -> String {
        "\(book?.id ?? "unknown")/\(chapterKey)/\(page.index).img"
    }

    private var chapterKey: String {
        switch loadSource {
        case .local: return "local"
        case .online(_, let chapterURL, _, _): return chapterKeyHash(chapterURL)
        }
    }

    private func chapterKeyHash(_ url: String) -> String {
        // 用作文件名片段，剔除非法字符；URL 可能较长，取路径部分即可。
        let tail = url.components(separatedBy: "/").last ?? url
        return ComicSafeName.clean(tail)
    }

    private func restoreProgress() {
        guard let book, !pages.isEmpty else { return }
        let target = Int((book.progress * Double(pages.count - 1)).rounded())
        currentIndex = min(max(target, 0), pages.count - 1)
    }

    func persistProgress() {
        guard let book, !pages.isEmpty else { return }
        book.progress = Double(currentIndex) / Double(max(pages.count - 1, 1))
        book.pageCount = pages.count
        try? PersistenceController.shared.context.save()
    }
}

/// P3.4 文件名片段清洗（与落盘 safeFileName 保持一致的轻量版，仅用于章节 key）。
enum ComicSafeName {
    static func clean(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "ch" : cleaned
    }
}
