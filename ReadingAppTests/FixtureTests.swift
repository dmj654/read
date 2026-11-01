import XCTest
import Foundation
@testable import ReadingApp

// MARK: - P0.21 测试夹具资产

final class FixtureTests: XCTestCase {

    private let fixtureNames = [
        "search.html", "book.html", "toc.html", "content.html",
        "source_novel.json", "source_comic.json"
    ]

    /// 夹具文件存在且非空。
    func testFixtureFilesExistAndNonEmpty() {
        for name in fixtureNames {
            let data = FixtureSupport.loadFixture(name)
            XCTAssertNotNil(data, "夹具缺失: \(name)")
            XCTAssertGreaterThan(data?.count ?? 0, 0, "夹具为空: \(name)")
        }
    }

    /// 样例 Legado 源 JSON 可被 SourceImporter 解析。
    func testSourceJSONFixturesParse() throws {
        let novelData = try XCTUnwrap(FixtureSupport.loadFixture("source_novel.json"))
        let novel = try SourceImporter.import(json: novelData)
        XCTAssertEqual(novel.name, "Demo Novel")
        XCTAssertEqual(novel.type, .novel)
        XCTAssertEqual(novel.searchUrl, "https://novel.demo.com/s?q={{key}}")

        let comicData = try XCTUnwrap(FixtureSupport.loadFixture("source_comic.json"))
        let comic = try SourceImporter.import(json: comicData)
        XCTAssertEqual(comic.name, "Demo Comic")
        XCTAssertEqual(comic.type, .comic)
    }

    /// 关键验收：夹具确实被解析引擎（P0.14–P0.20）消费。
    func testReplayFromFixtures() {
        let search = FixtureSupport.loadFixtureString("search.html")!
        XCTAssertEqual(RuleEngine.evaluate("//li/a", source: search),
                       ["Book One", "Book Two", "Book Three"])

        let toc = FixtureSupport.loadFixtureString("toc.html")!
        XCTAssertEqual(RuleEngine.evaluate("//li/a", source: toc),
                       ["Chapter 1", "Chapter 2", "Chapter 3"])

        let content = FixtureSupport.loadFixtureString("content.html")!
        XCTAssertEqual(RuleEngine.evaluate("//div[@id=\"content\"]/p", source: content),
                       ["First paragraph.", "Second paragraph.", "Third paragraph."])

        let book = FixtureSupport.loadFixtureString("book.html")!
        let info = CompositeRule.parse(book, rule: """
        name: //h1[@class="name"]
        author: //span[@class="author"]
        intro: //div[@class="intro"]
        """)
        XCTAssertEqual(info.title, "Demo Book")
        XCTAssertEqual(info.author, "Jane Doe")
        XCTAssertEqual(info.intro, "A demo story intro.")
    }
}
