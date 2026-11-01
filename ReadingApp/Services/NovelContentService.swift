import Foundation

/// P1.5 目录项。
struct Chapter: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let url: String
}

/// P1.5 目录规则（解码自 `SourceRule.ruleToc` 的 JSON 字符串），平行列表抽取（标题 + 链接）。
struct TocRule: Decodable, Sendable {
    let chapterName: String?
    let chapterUrl: String?

    init?(from jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TocRule.self, from: data) else { return nil }
        self = decoded
    }
}

/// P1.5 小说内容服务：目录与章节正文的抓取 + RuleEngine 抽取。
struct NovelContentService {
    let network: NetworkService

    init(network: NetworkService = NetworkService()) { self.network = network }

    func fetchTOC(bookURL: String, source: SourceRule) async throws -> [Chapter] {
        guard let url = URL(string: bookURL) else { return [] }
        let (data, _) = try await network.data(for: Request(url: url))
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let rule = TocRule(from: source.ruleToc)
        let names = rule?.chapterName.map { RuleEngine.evaluate($0, source: html) } ?? []
        let urls = rule?.chapterUrl.map { RuleEngine.evaluate($0, source: html) } ?? []
        let count = max(names.count, urls.count)

        var chapters: [Chapter] = []
        for i in 0..<count {
            let title = i < names.count ? names[i] : "第\(i + 1)章"
            let u = i < urls.count ? urls[i] : ""
            guard !u.isEmpty else { continue }
            chapters.append(Chapter(title: title, url: u))
        }
        return chapters
    }

    func fetchContent(chapterURL: String, source: SourceRule) async throws -> String {
        guard let url = URL(string: chapterURL) else { return "" }
        let (data, _) = try await network.data(for: Request(url: url))
        guard let html = String(data: data, encoding: .utf8) else { return "" }
        return RuleEngine.joined(source.ruleContent, source: html)
    }
}
