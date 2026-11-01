import Foundation
import Observation

/// P1.3/P1.8 书详情 ViewModel：抓取 BookInfo 并提供「加入书架」。
@Observable
final class BookDetailViewModel {
    private let detailService: BookDetailService
    private let bookshelf: BookshelfStore
    let source: SourceRule
    let bookURL: String
    var info: BookInfo?
    var isLoading = false
    var savedBook: Book?

    init(detailService: BookDetailService = BookDetailService(),
         bookshelf: BookshelfStore, source: SourceRule, bookURL: String) {
        self.detailService = detailService
        self.bookshelf = bookshelf
        self.source = source
        self.bookURL = bookURL
    }

    @MainActor
    func load() async {
        isLoading = true
        defer { isLoading = false }
        info = try? await detailService.fetchDetail(bookURL: bookURL, source: source)
    }

    func addToShelf() {
        guard let info else { return }
        savedBook = try? bookshelf.addOrUpdate(info, sourceID: source.id, bookURL: bookURL, type: source.type)
    }
}
