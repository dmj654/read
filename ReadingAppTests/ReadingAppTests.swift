import XCTest
@testable import ReadingApp

/// P0.1 冒烟测试：验证工程骨架、基础类型与编译链路。
final class ReadingAppTests: XCTestCase {

    /// 占位断言：真实启动 / UI 测试将在后续阶段补充。
    func testScaffoldExists() {
        XCTAssertTrue(true)
    }

    /// 验证基础枚举可正确编解码（为 P0.3 模型预热）。
    func testContentTypeDecodable() throws {
        let novel = try JSONDecoder().decode(ContentType.self, from: Data("\"novel\"".utf8))
        XCTAssertEqual(novel, .novel)

        let comic = try JSONDecoder().decode(ContentType.self, from: Data("\"comic\"".utf8))
        XCTAssertEqual(comic, .comic)
    }
}
