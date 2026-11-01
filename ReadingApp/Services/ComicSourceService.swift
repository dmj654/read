import Foundation

/// P3.1 漫画章节（与小说 `Chapter` 平行结构，复用 `ruleToc` 抽取）。
struct ComicChapter: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let url: String
}

/// P3.1 漫画图片页：一话（章节）由若干图片页顺序构成。
struct ComicImagePage: Identifiable, Sendable {
    let index: Int
    let imageURL: String
    var isAd: Bool
    var id: Int { index }
}

/// P3.1 漫画书源解析服务。
///
/// 复用与小说同源的 `SourceRule` 与 `RuleEngine`，仅补充漫画专属字段的解析逻辑：
/// - 章节列表：复用 `ruleToc`（标题 + 链接平行列表）。
/// - 图片页列表：`imageListRule` 抽图片容器 → `imageUrlRule` 从容器内抽真实图片 URL →
///   `nextPageRule` 抽取「下一页」链接并循环（带最大页数保护防死循环）→ `adPageFilter` 剔除广告页。
struct ComicSourceService {
    let network: NetworkService

    init(network: NetworkService = NetworkService()) { self.network = network }

    // MARK: 章节列表（复用小说 TOC 规则）

    func fetchChapterList(bookURL: String, source: SourceRule) async throws -> [ComicChapter] {
        guard let url = URL(string: bookURL) else { return [] }
        let (data, _) = try await network.data(for: Request(url: url))
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let rule = TocRule(from: source.ruleToc)
        let names = rule?.chapterName.map { RuleEngine.evaluate($0, source: html) } ?? []
        let urls = rule?.chapterUrl.map { RuleEngine.evaluate($0, source: html) } ?? []
        let count = max(names.count, urls.count)

        var chapters: [ComicChapter] = []
        for i in 0..<count {
            let title = i < names.count ? names[i] : "第\(i + 1)话"
            let u = i < urls.count ? urls[i] : ""
            guard !u.isEmpty else { continue }
            chapters.append(ComicChapter(title: title, url: u))
        }
        return chapters
    }

    // MARK: 图片页列表（漫画专属字段）

    /// 抓取某章节的图片页列表（含分页循环与广告过滤）。
    /// - Parameter maxPages: 单话分页上限，防止 `nextPageRule` 形成死循环。
    func fetchImagePages(chapterURL: String, source: SourceRule, maxPages: Int = 20) async throws -> [ComicImagePage] {
        guard let base = URL(string: chapterURL), !base.absoluteString.isEmpty else { return [] }
        var pages: [ComicImagePage] = []
        var currentURL: URL? = base
        var guardCounter = 0

        while let url = currentURL, guardCounter < maxPages {
            guardCounter += 1
            let (data, _) = try await network.data(for: Request(url: url))
            guard let html = String(data: data, encoding: .utf8) else { break }

            // 先按 imageListRule 取图片容器的外部 HTML（空规则则整页为单一容器），
            // 再在每个容器内用 imageUrlRule 抽真实图片 URL。
            let containers = RuleEngine.evaluateElements(source.imageListRule ?? "", source: html)
            for container in containers {
                let imageURLs = RuleEngine.evaluate(source.imageUrlRule ?? "", source: container)
                for imageURL in imageURLs where !imageURL.isEmpty {
                    pages.append(ComicImagePage(index: pages.count, imageURL: imageURL, isAd: false))
                }
            }

            // 下一页：抽首个非空链接，必须是与当前页不同的合法 URL。
            if let nextRule = source.nextPageRule, !nextRule.isEmpty,
               let next = RuleEngine.first(nextRule, source: html), !next.isEmpty,
               let nextURL = URL(string: next, relativeTo: url), nextURL != url {
                currentURL = nextURL
            } else {
                currentURL = nil
            }
        }
        return filterAds(pages, rule: source.adPageFilter)
    }

    // MARK: 广告页过滤

    /// 命中 `adPageFilter` 的页面视为广告页并剔除。
    /// 规则语义：以 `/` 开头按正则匹配，否则按大小写不敏感子串包含判定。
    private func filterAds(_ pages: [ComicImagePage], rule: String?) -> [ComicImagePage] {
        guard let rule, !rule.isEmpty else { return pages }
        return pages.filter { !ComicAdFilter.isAd($0.imageURL, rule: rule) }
    }
}
