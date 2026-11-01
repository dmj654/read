import XCTest
import Foundation
@testable import ReadingApp

// MARK: - P0.20 端到端规则回放套件（≥20 例，覆盖 search/toc/content/bookInfo 四类）

private struct ReplayCase {
    let name: String
    let category: String      // search / toc / content / bookInfo
    let html: String
    let rule: String
    let expected: [String]
}

final class ReplaySuiteTests: XCTestCase {

    private let bookHTML = """
    <div class="book">
      <h1 class="name">My Book</h1>
      <span class="author">John</span>
      <div class="intro">A nice story</div>
    </div>
    """

    private let cases: [ReplayCase] = [
        // —— search ——
        ReplayCase(name: "search-xpath-list", category: "search",
                   html: "<ul><li>Book A</li><li>Book B</li></ul>",
                   rule: "//li", expected: ["Book A", "Book B"]),
        ReplayCase(name: "search-css-list", category: "search",
                   html: "<ul><li>Book A</li><li>Book B</li></ul>",
                   rule: "css>li", expected: ["Book A", "Book B"]),
        ReplayCase(name: "search-xpath-class", category: "search",
                   html: "<div class=\"item\">X</div><div class=\"other\">Y</div>",
                   rule: "//div[@class=\"item\"]", expected: ["X"]),
        ReplayCase(name: "search-regex-digits", category: "search",
                   html: "<p>id=12 and 34</p>",
                   rule: "/\\d+/", expected: ["12", "34"]),
        ReplayCase(name: "search-xpath-span", category: "search",
                   html: "<div><span>One</span><span>Two</span></div>",
                   rule: "//span", expected: ["One", "Two"]),
        ReplayCase(name: "search-css-descendant", category: "search",
                   html: "<div><p class=\"x\">A</p><p class=\"x\">B</p></div>",
                   rule: "css>div p.x", expected: ["A", "B"]),

        // —— toc ——
        ReplayCase(name: "toc-xpath-a", category: "toc",
                   html: "<ol><li><a>Ch1</a></li><li><a>Ch2</a></li></ol>",
                   rule: "//li/a", expected: ["Ch1", "Ch2"]),
        ReplayCase(name: "toc-regex-href", category: "toc",
                   html: "<a href=\"/c1\">Ch1</a><a href=\"/c2\">Ch2</a>",
                   rule: "/href=\"([^\"]+)\"/", expected: ["/c1", "/c2"]),
        ReplayCase(name: "toc-css-a", category: "toc",
                   html: "<a href=\"/c1\">Ch1</a><a href=\"/c2\">Ch2</a>",
                   rule: "css>a", expected: ["Ch1", "Ch2"]),

        // —— content ——
        ReplayCase(name: "content-xpath-p", category: "content",
                   html: "<div id=\"content\"><p>a</p><p>b</p><p>c</p></div>",
                   rule: "//div[@id=\"content\"]/p", expected: ["a", "b", "c"]),
        ReplayCase(name: "content-regex-strip-comment", category: "content",
                   html: "<p>Hello<!--c-->World</p>",
                   rule: "<!--.*?-->##", expected: ["HelloWorld"]),
        ReplayCase(name: "content-js-transform", category: "content",
                   html: "  spaced  ",
                   rule: "@js:result.replace(/\\s+/g,'').toUpperCase()", expected: ["SPACED"]),
        ReplayCase(name: "content-xpath-then-js-trim", category: "content",
                   html: "<h2>  Title  </h2>",
                   rule: "//h2@js:result.trim()", expected: ["Title"]),
        ReplayCase(name: "content-css-then-js-trim", category: "content",
                   html: "<span>  x  </span>",
                   rule: "css>span@js:result.trim()", expected: ["x"]),
        ReplayCase(name: "content-regex-single", category: "content",
                   html: "price:99 yuan",
                   rule: "/(\\d+)/", expected: ["99"]),
        ReplayCase(name: "content-regex-flags-i", category: "content",
                   html: "Hello WORLD",
                   rule: "/world/i", expected: ["WORLD"]),
        ReplayCase(name: "content-regex-flags-m", category: "content",
                   html: "a=1\nb=2",
                   rule: "/^(\\w)/m", expected: ["a", "b"]),
        ReplayCase(name: "content-regex-backref", category: "content",
                   html: "user: bob",
                   rule: "user: (.*)##Name: $1", expected: ["Name: bob"]),
        ReplayCase(name: "content-xpath-children", category: "content",
                   html: "<book><name>N</name><author>A</author></book>",
                   rule: "//book/*", expected: ["N", "A"]),
        ReplayCase(name: "content-literal", category: "content",
                   html: "https://img/x.jpg",
                   rule: "https://img/x.jpg", expected: ["https://img/x.jpg"]),
        ReplayCase(name: "content-regex-prefix", category: "content",
                   html: "Name: Alice",
                   rule: "Name:\\s*##", expected: ["Alice"]),
        ReplayCase(name: "content-xpath-a-text", category: "content",
                   html: "<a href=\"/x\">T</a>",
                   rule: "//a", expected: ["T"]),

        // —— bookInfo ——
        ReplayCase(name: "bookinfo-single-field", category: "bookInfo",
                   html: "<div class=\"book\"><h1 class=\"name\">My Book</h1></div>",
                   rule: "//h1[@class=\"name\"]", expected: ["My Book"]),
    ]

    func testReplayAll() {
        XCTAssertGreaterThanOrEqual(cases.count, 20, "回放样例须 ≥20 条")
        var byCategory: [String: Int] = [:]
        for c in cases {
            byCategory[c.category, default: 0] += 1
            let got = RuleEngine.evaluate(c.rule, source: c.html)
            XCTAssertEqual(got, c.expected, "回放失败: \(c.name) [\(c.category)]")
        }
        // 四类均覆盖
        for cat in ["search", "toc", "content", "bookInfo"] {
            XCTAssertGreaterThan(byCategory[cat] ?? 0, 0, "缺少类别: \(cat)")
        }
    }

    func testReplayCompositeBookInfo() {
        let rule = """
        name: //h1[@class="name"]
        author: //span[@class="author"]
        intro: //div[@class="intro"]
        cover: https://img.example.com/cover.jpg
        """
        let info = CompositeRule.parse(bookHTML, rule: rule)
        XCTAssertEqual(info.title, "My Book")
        XCTAssertEqual(info.author, "John")
        XCTAssertEqual(info.intro, "A nice story")
        XCTAssertEqual(info.coverURL, "https://img.example.com/cover.jpg")
    }
}
