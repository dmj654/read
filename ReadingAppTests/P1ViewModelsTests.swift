import XCTest
import Foundation
import SwiftData
@testable import ReadingApp

// MARK: - P1 ViewModel 逻辑单元测试

final class P1ViewModelsTests: XCTestCase {

    // MARK: P1.4 BookshelfViewModel
    func testBookshelfViewModel() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let store = BookshelfStore(context: ctx)
        let vm = BookshelfViewModel(store: store)
        vm.load()
        XCTAssertTrue(vm.filtered.isEmpty)

        let b = Book(title: "Book A", author: "Author", type: .novel, sourceID: "s")
        ctx.insert(b); try ctx.save()
        vm.load()
        XCTAssertEqual(vm.filtered.count, 1)

        vm.query = "Book"; XCTAssertEqual(vm.filtered.count, 1)
        vm.query = "zzz"; XCTAssertEqual(vm.filtered.count, 0)
        vm.query = ""
        vm.remove(b)
        XCTAssertTrue(vm.filtered.isEmpty)
    }

    // MARK: P1.2/P1.8 SearchViewModel（StubNetwork）
    func testSearchViewModel() async throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let repo = SourceRepository(context: ctx)
        let html = #"<ul><li><a href="/b1">Book One</a></li></ul>"#
        let resp = HTTPURLResponse.fixture(status: 200, url: URL(string: "https://x.com")!)
        let svc = SearchService(network: NetworkService(session: StubSession(response: (Data(html.utf8), resp))))
        let source = SourceRule(name: "S", type: .novel, enabled: true,
                                searchUrl: "https://x.com/s?q={{key}}",
                                ruleSearch: #"{"searchUrl":"https://x.com/s?q={{key}}","name":"//li/a","bookUrl":"//li/a@href"}"#)
        ctx.insert(source); try ctx.save()

        let vm = SearchViewModel(service: svc, repository: repo)
        vm.keyword = "demo"
        await vm.search()
        XCTAssertEqual(vm.results.count, 1)
        XCTAssertEqual(vm.results.first?.title, "Book One")

        // 空关键词早退
        let vm2 = SearchViewModel(service: svc, repository: repo)
        await vm2.search()
        XCTAssertTrue(vm2.results.isEmpty)
    }

    // MARK: P1.5/P1.6/P1.8 NovelReaderViewModel 导航逻辑
    func testNovelReaderViewModelNavigation() {
        let vm = NovelReaderViewModel(source: SourceRule(name: "S"))
        vm.chapters = [Chapter(title: "A", url: "/a"), Chapter(title: "B", url: "/b")]
        vm.pages = ["p0", "p1", "p2"]
        XCTAssertEqual(vm.currentPage, 0)
        vm.nextPage(); XCTAssertEqual(vm.currentPage, 1)
        vm.nextPage(); vm.nextPage(); XCTAssertEqual(vm.currentPage, 2)  // 末页夹紧
        vm.prevPage(); XCTAssertEqual(vm.currentPage, 1)
        XCTAssertEqual(vm.progress, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(vm.currentChapterTitle, "A")
    }

    // MARK: P1.7 ReaderSettings 默认基线
    func testReaderSettingsDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.fontSize, 17)
        XCTAssertEqual(s.lineSpacing, 1.5)
        XCTAssertEqual(s.pageTurnMode, "curl")
    }
}
