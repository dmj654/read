import Foundation
import SwiftData

/// P1.3 书详情抓取：用 `ruleBookInfo` 复合规则抽取 BookInfo。
struct BookDetailService {
    let network: NetworkService

    init(network: NetworkService = NetworkService()) { self.network = network }

    func fetchDetail(bookURL: String, source: SourceRule) async throws -> BookInfo {
        guard let url = URL(string: bookURL) else { throw NetworkError.badStatus(0) }
        let (data, _) = try await network.data(for: Request(url: url))
        guard let html = String(data: data, encoding: .utf8) else { throw NetworkError.badStatus(0) }
        return CompositeRule.parse(html, rule: source.ruleBookInfo)
    }
}

/// P1.4 书架本地仓储：Book 的增删改查与进度更新（复用 Book + PersistenceController）。
final class BookshelfStore {
    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func allBooks() throws -> [Book] {
        try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    /// 以 (sourceID + title) 去重 upsert 为本地 Book；记录详情链接与内容类型（P4 双体系收口）。
    @discardableResult
    func addOrUpdate(_ info: BookInfo, sourceID: String, bookURL: String, type: ContentType = .novel) throws -> Book {
        let title = info.title ?? "未命名"
        if let existing = try context.fetch(FetchDescriptor<Book>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.title == title }
        )).first {
            existing.title = title
            existing.author = info.author ?? existing.author
            existing.coverURL = info.coverURL ?? existing.coverURL
            existing.bookURL = bookURL
            existing.type = type
            existing.updatedAt = .now
            try context.save()
            return existing
        }
        let book = Book(title: title, author: info.author ?? "", type: type,
                        sourceID: sourceID, coverURL: info.coverURL, bookURL: bookURL)
        context.insert(book)
        try context.save()
        return book
    }

    func bookByURL(_ bookURL: String, sourceID: String) throws -> Book? {
        try context.fetch(FetchDescriptor<Book>(
            predicate: #Predicate { $0.sourceID == sourceID }
        )).first
    }

    func updateProgress(_ book: Book, progress: Double) throws {
        book.progress = min(max(progress, 0), 1)
        book.updatedAt = .now
        try context.save()
    }

    func remove(_ book: Book) throws {
        context.delete(book)
        try context.save()
    }
}
