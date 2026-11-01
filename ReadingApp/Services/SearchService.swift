import Foundation

/// P1.2 跨源归一化的搜索结果。
struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let author: String?
    let coverURL: String?
    let bookURL: String
    let sourceID: String
}

/// P1.2 搜索规则（解码自 `SourceRule.ruleSearch` 的 JSON 字符串）。
/// 采用「平行列表」抽取：name / author / bookUrl / coverUrl 各自在全页上求值后按索引 zip。
struct SearchRule: Decodable, Sendable {
    let searchUrl: String?
    let name: String?
    let author: String?
    let bookUrl: String?
    let coverUrl: String?

    init?(from jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SearchRule.self, from: data) else { return nil }
        self = decoded
    }
}

/// P1.2 搜索服务：遍历启用书源，抓取搜索页并用 RuleEngine 抽取结果。
struct SearchService {
    let network: NetworkService

    init(network: NetworkService = NetworkService()) { self.network = network }

    func search(keyword: String, sources: [SourceRule]) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        for source in sources {
            guard let rule = SearchRule(from: source.ruleSearch),
                  let template = rule.searchUrl,
                  let nameRule = rule.name else { continue }

            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            let urlString = template.replacingOccurrences(of: "{{key}}", with: encoded)
            guard let url = URL(string: urlString) else { continue }

            let (data, _) = try await network.data(for: Request(url: url))
            guard let html = String(data: data, encoding: .utf8) else { continue }

            let names = RuleEngine.evaluate(nameRule, source: html)
            let authors = rule.author.map { RuleEngine.evaluate($0, source: html) } ?? []
            let urls = rule.bookUrl.map { RuleEngine.evaluate($0, source: html) } ?? []
            let covers = rule.coverUrl.map { RuleEngine.evaluate($0, source: html) } ?? []

            let count = max(names.count, urls.count)
            for i in 0..<count {
                let title = i < names.count ? names[i] : ""
                let author = i < authors.count ? authors[i] : nil
                let bookURL = i < urls.count ? urls[i] : nil
                let cover = i < covers.count ? covers[i] : nil
                guard let bookURL, !bookURL.isEmpty else { continue }
                results.append(SearchResult(title: title, author: author,
                                           coverURL: cover, bookURL: bookURL, sourceID: source.id))
            }
        }
        return results
    }
}
