import XCTest
import Foundation
import SwiftData
@testable import ReadingApp

// MARK: - P1 服务层 + 分页 + 引擎属性扩展 单元测试

final class P1ServicesTests: XCTestCase {

    // MARK: 引擎属性抽取（P1 新增能力）
    func testEngineAttributeExtraction() {
        let html = #"<ul><li><a href="/b1">A</a></li><li><a href="/b2">B</a></li></ul>"#
        XCTAssertEqual(RuleEngine.evaluate("//li/a@href", source: html), ["/b1", "/b2"])
        XCTAssertEqual(RuleEngine.evaluate("//li/a", source: html), ["A", "B"])
    }

    // MARK: P1.1 SourceRepository
    func testSourceRepositoryCRUD() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let repo = SourceRepository(context: ctx)
        let json = #"{"bookSourceName":"S1","bookSourceUrl":"https://s.com","bookSourceType":1}"#.data(using: .utf8)!
        let rule = try repo.importSource(json: json)
        XCTAssertEqual(try repo.allSources().count, 1)
        XCTAssertEqual(try repo.enabledSources().count, 1)   // 默认启用

        try repo.toggle(rule, enabled: false)
        XCTAssertEqual(try repo.enabledSources().count, 0)

        try repo.delete(rule)
        XCTAssertEqual(try repo.allSources().count, 0)
    }

    // MARK: P1.2 SearchService（StubSession 零网络）
    func testSearchService() async throws {
        let html = #"<ul><li><a href="/b1">Book One</a></li><li><a href="/b2">Book Two</a></li></ul>"#
        let resp = HTTPURLResponse.fixture(status: 200, url: URL(string: "https://x.com")!)
        let svc = SearchService(network: NetworkService(session: StubSession(response: (Data(html.utf8), resp))))
        let rule = SourceRule(name: "S", type: .novel, enabled: true,
                              searchUrl: "https://x.com/s?q={{key}}",
                              ruleSearch: #"{"searchUrl":"https://x.com/s?q={{key}}","name":"//li/a","bookUrl":"//li/a@href"}"#)
        let results = try await svc.search(keyword: "demo", sources: [rule])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.title), ["Book One", "Book Two"])
        XCTAssertEqual(results.map(\.bookURL), ["/b1", "/b2"])
    }

    // MARK: P1.3 BookDetailService
    func testBookDetailService() async throws {
        let html = #"<div class="book"><h1 class="name">My Book</h1><span class="author">Jane</span><div class="intro">Intro text</div></div>"#
        let resp = HTTPURLResponse.fixture(status: 200, url: URL(string: "https://x.com")!)
        let svc = BookDetailService(network: NetworkService(session: StubSession(response: (Data(html.utf8), resp))))
        let rule = SourceRule(name: "S", ruleBookInfo: """
        name: //h1[@class="name"]
        author: //span[@class="author"]
        intro: //div[@class="intro"]
        """)
        let info = try await svc.fetchDetail(bookURL: "https://x.com/b", source: rule)
        XCTAssertEqual(info.title, "My Book")
        XCTAssertEqual(info.author, "Jane")
        XCTAssertEqual(info.intro, "Intro text")
    }

    // MARK: P1.3 BookshelfStore upsert 去重
    func testBookshelfStoreUpsert() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let store = BookshelfStore(context: ctx)
        let info = BookInfo(title: "T", author: "A", intro: nil, coverURL: nil, status: nil, category: nil)
        let b1 = try store.addOrUpdate(info, sourceID: "s1", bookURL: "u1")
        XCTAssertEqual(try store.allBooks().count, 1)
        // 同 sourceID+title 再次 upsert → 更新不新增
        var info2 = info; info2.intro = "x"
        let b2 = try store.addOrUpdate(info2, sourceID: "s1", bookURL: "u1")
        XCTAssertEqual(b1.id, b2.id)
        XCTAssertEqual(try store.allBooks().count, 1)

        try store.updateProgress(b1, progress: 0.5)
        XCTAssertEqual(b1.progress, 0.5)

        try store.remove(b1)
        XCTAssertEqual(try store.allBooks().count, 0)
    }

    // MARK: P1.5 NovelContentService
    func testNovelContentService() async throws {
        let tocHTML = #"<ol><li><a href="/c1">Ch1</a></li><li><a href="/c2">Ch2</a></li></ol>"#
        let contentHTML = #"<div id="content"><p>A</p><p>B</p></div>"#
        var call = 0
        let session = DualStub(html1: tocHTML, html2: contentHTML)
        let svc = NovelContentService(network: NetworkService(session: session))
        let rule = SourceRule(name: "S", type: .novel,
                              ruleToc: #"{"chapterName":"//li/a","chapterUrl":"//li/a@href"}"#,
                              ruleContent: #"//div[@id="content"]/p"#)
        let toc = try await svc.fetchTOC(bookURL: "https://x.com/b", source: rule)
        XCTAssertEqual(toc.map(\.title), ["Ch1", "Ch2"])
        XCTAssertEqual(toc.map(\.url), ["/c1", "/c2"])

        let content = try await svc.fetchContent(chapterURL: "/c1", source: rule)
        XCTAssertEqual(content, "A\nB")
    }

    // MARK: P1.6 ReaderPagination
    func testReaderPagination() {
        XCTAssertEqual(ReaderPagination.paginate("a\nb\nc", charsPerPage: 1), ["a", "b", "c"])
        XCTAssertEqual(ReaderPagination.paginate("a\nb\nc", charsPerPage: 100), ["a\nb\nc"])
        XCTAssertEqual(ReaderPagination.paginate("hello\nworld", charsPerPage: 3), ["hello", "world"])
        XCTAssertEqual(ReaderPagination.paginate("txt", charsPerPage: 0), ["txt"])  // 零宽度保护
    }
}

/// 测试桩：第 1 次返回 html1，之后返回 html2（用于目录→正文顺序）。
final class DualStub: URLSessionProtocol, @unchecked Sendable {
    let html1: String
    let html2: String
    private let lock = NSLock()
    private var count = 0
    init(html1: String, html2: String) { self.html1 = html1; self.html2 = html2 }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); count += 1; let n = count; lock.unlock()
        let body = n == 1 ? html1 : html2
        let resp = HTTPURLResponse.fixture(status: 200, url: request.url!)
        return (Data(body.utf8), resp)
    }
}
