import Foundation
import SwiftData
import Observation

enum BookshelfViewMode: String, CaseIterable { case grid, list }

/// P1.4 书架 ViewModel：本地 Book 列表、过滤、增删（双视图状态）。
@Observable
final class BookshelfViewModel {
    private let store: BookshelfStore
    var books: [Book] = []
    var viewMode: BookshelfViewMode = .grid
    var query: String = ""

    init(store: BookshelfStore) { self.store = store }

    func load() {
        books = (try? store.allBooks()) ?? []
    }

    var filtered: [Book] {
        guard !query.isEmpty else { return books }
        return books.filter { ($0.title + $0.author).localizedCaseInsensitiveContains(query) }
    }

    func remove(_ book: Book) {
        try? store.remove(book)
        load()
    }
}
