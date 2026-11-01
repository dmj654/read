import XCTest
import Foundation
import JavaScriptCore
@testable import ReadingApp

// MARK: - P0-D 解析引擎单元测试

final class RuleEngineTests: XCTestCase {

    // MARK: P0.13 分词器（≥6 样本）
    func testTokenizerSamples() {
        XCTAssertEqual(RuleTokenizer.tokenize("//h1"), [.xpath("//h1")])
        XCTAssertEqual(RuleTokenizer.tokenize("css>li.b"), [.css("li.b")])
        XCTAssertEqual(RuleTokenizer.tokenize("/world/i"), [.regex(pattern: "world", flags: "i")])
        XCTAssertEqual(RuleTokenizer.tokenize("//h1@js:result.trim()"),
                       [.xpath("//h1"), .js("result.trim()")])
        XCTAssertEqual(RuleTokenizer.tokenize("Name:\\s*##"), [.replace(pattern: "Name:\\s*", replacement: "")])
        XCTAssertEqual(RuleTokenizer.tokenize("https://x"), [.literal("https://x")])
    }

    // MARK: P0.14 正则求值
    func testRegexCaptureMulti() {
        let r = RuleEngine.evaluate("/\\d+/", source: "<p>id=12 and 34</p>")
        XCTAssertEqual(r, ["12", "34"])
    }

    func testRegexFlagsCaseInsensitive() {
        let r = RuleEngine.evaluate("/world/i", source: "Hello WORLD")
        XCTAssertEqual(r, ["WORLD"])
    }

    func testRegexFlagsMultiline() {
        let r = RuleEngine.evaluate("/^(\\w)/m", source: "a=1\nb=2")
        XCTAssertEqual(r, ["a", "b"])
    }

    func testRegexReplace() {
        let r = RuleEngine.evaluate("Name:\\s*##", source: "Name: Alice")
        XCTAssertEqual(r, ["Alice"])
    }

    func testRegexReplaceBackreference() {
        let r = RuleEngine.evaluate("user: (.*)##Name: $1", source: "user: bob")
        XCTAssertEqual(r, ["Name: bob"])
    }

    // MARK: P0.15 XPath 求值
    func testXPathList() {
        let html = "<ul><li>A</li><li>B</li></ul>"
        XCTAssertEqual(RuleEngine.evaluate("//li", source: html), ["A", "B"])
    }

    func testXPathSingle() {
        let html = "<div class=\"book\"><h1>Hi</h1></div>"
        XCTAssertEqual(RuleEngine.evaluate("//h1", source: html), ["Hi"])
    }

    func testXPathEmpty() {
        let html = "<div></div>"
        XCTAssertEqual(RuleEngine.evaluate("//p", source: html), [])
    }

    // MARK: P0.16 CSS 求值（与 XPath 对齐）
    func testCssList() {
        let html = "<ul><li>A</li><li>B</li></ul>"
        XCTAssertEqual(RuleEngine.evaluate("css>li", source: html), ["A", "B"])
        // 与 XPath 版本结果一致
        XCTAssertEqual(RuleEngine.evaluate("css>li", source: html),
                       RuleEngine.evaluate("//li", source: html))
    }

    // MARK: P0.17 JS 注入（沙箱）
    /// 环境探针：只验证 JavaScriptCore 在本模拟器 runtime 上可用。
    ///
    /// 单独存在的理由：JSC 出问题时是**进程级崩溃**，会把整个 xctest 进程带走，
    /// 日志里只剩一句 "Test crashed with signal segv"，无法区分「沙箱环境不可用」
    /// 与「我们的规则引擎写错了」。XCTest 按选择器名字典序执行，
    /// `testJSCEnvironmentProbe` 排在 `testJSInvalidDoesNotCrash` 之前，
    /// 因此一旦崩溃发生在探针之后，就说明 JSC 本身能跑，问题在规则引擎这一侧。
    func testJSCEnvironmentProbe() {
        guard let context = JSContext() else {
            XCTFail("JavaScriptCore 无法创建 JSContext（该 runtime 上 JSC 不可用）")
            return
        }
        XCTAssertEqual(context.evaluateScript("1 + 1")?.toInt32(), 2)
    }

    func testJSTransform() {
        let r = RuleEngine.evaluate("@js:result.replace(/\\s+/g,'').toUpperCase()", source: "  spaced  ")
        XCTAssertEqual(r, ["SPACED"])
    }

    func testJSPassthrough() {
        XCTAssertEqual(RuleEngine.evaluate("@js:result", source: "abc"), ["abc"])
    }

    func testJSInvalidDoesNotCrash() {
        let r = RuleEngine.evaluate("@js:this is not valid js !!", source: "x")
        XCTAssertTrue(r.isEmpty)
    }

    // MARK: P0.18 复合规则拼装
    func testCompositeBookInfo() {
        let html = """
        <div class="book">
          <h1 class="name">My Book</h1>
          <span class="author">John</span>
          <div class="intro">A nice story</div>
        </div>
        """
        let rule = """
        name: //h1[@class="name"]
        author: //span[@class="author"]
        intro: //div[@class="intro"]
        """
        let info = CompositeRule.parse(html, rule: rule)
        XCTAssertEqual(info.title, "My Book")
        XCTAssertEqual(info.author, "John")
        XCTAssertEqual(info.intro, "A nice story")
    }

    func testCompositeLiteralCover() {
        let html = "<h1 class=\"name\">X</h1>"
        let rule = """
        name: //h1[@class="name"]
        cover: https://img.example.com/cover.jpg
        """
        let info = CompositeRule.parse(html, rule: rule)
        XCTAssertEqual(info.title, "X")
        XCTAssertEqual(info.coverURL, "https://img.example.com/cover.jpg")
    }

    // MARK: P0.19 书源 JSON 导入
    func testImportNovelSource() throws {
        let json = """
        {
          "bookSourceName": "Test Novel",
          "bookSourceUrl": "https://novel.example.com",
          "bookSourceType": 1,
          "enabled": true,
          "ruleSearch": { "searchUrl": "https://novel.example.com/s?q={{key}}", "bookList": "//li" },
          "ruleBookInfo": "name: //h1",
          "ruleToc": "//li/a",
          "ruleContent": "//div[@id=content]"
        }
        """.data(using: .utf8)!
        let rule = try SourceImporter.import(json: json)
        XCTAssertEqual(rule.name, "Test Novel")
        XCTAssertEqual(rule.type, .novel)
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.searchUrl, "https://novel.example.com/s?q={{key}}")
        XCTAssertTrue(rule.ruleSearch.contains("searchUrl"))
        XCTAssertEqual(rule.ruleBookInfo, "name: //h1")
        XCTAssertEqual(rule.ruleToc, "//li/a")
        XCTAssertEqual(rule.ruleContent, "//div[@id=content]")
    }

    func testImportComicSource() throws {
        let json = """
        {
          "bookSourceName": "Test Comic",
          "bookSourceUrl": "https://comic.example.com",
          "bookSourceType": 3,
          "ruleSearch": { "searchUrl": "https://comic.example.com/s" }
        }
        """.data(using: .utf8)!
        let rule = try SourceImporter.import(json: json)
        XCTAssertEqual(rule.name, "Test Comic")
        XCTAssertEqual(rule.type, .comic)            // 3 → 漫画
        XCTAssertTrue(rule.enabled)                  // 缺失默认 true
    }

    func testImportDefaultsWhenMissing() throws {
        let json = """
        {
          "bookSourceName": "Minimal",
          "bookSourceUrl": "https://min.example.com"
        }
        """.data(using: .utf8)!
        let rule = try SourceImporter.import(json: json)
        XCTAssertEqual(rule.type, .novel)            // 缺失默认小说
        XCTAssertTrue(rule.enabled)                  // 缺失默认 true
        XCTAssertEqual(rule.searchUrl, "https://min.example.com")  // 兜底为源站地址
    }

    func testImportInvalidJSONThrows() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try SourceImporter.import(json: bad)) { err in
            XCTAssertEqual(err as? SourceImporterError, .invalidJSON)
        }
    }
}
