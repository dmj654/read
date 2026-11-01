import XCTest
import Kanna
import ZIPFoundation
import Logging

/// P0.2 依赖接入测试：验证三个 SPM 模块可被应用/测试目标正确链接与编译。
///
/// - Kanna (MIT)：后续 P0.15 / P0.16 用于 XPath / CSS 解析。
/// - ZIPFoundation (MIT)：后续 P3 用于 CBZ / ZIP 解包。
/// - swift-log (Apache-2.0)：后续 P0.11 用于本地可审计日志（绝不外发）。
final class DependenciesCompileTests: XCTestCase {

    /// Kanna 符号可实例化（不触发网络，仅验证模块链接）。
    func testKannaLinkable() throws {
        let doc = try HTML(html: "<p>hello</p>", encoding: .utf8)
        XCTAssertEqual(doc.at_css("p")?.text, "hello")
    }

    /// ZIPFoundation 模块可链接（Archive 能力在 P3 落地）。
    func testZIPFoundationLinkable() {
        // Archive 类型在 P3 使用，此处只验证模块 import 与符号存在。
        XCTAssertTrue(true)
    }

    /// swift-log 可创建 Logger 并输出（本地，不外发）。
    func testSwiftLogLinkable() {
        var logger = Logger(label: "com.example.ReadingApp.deps")
        logger.info("SPM dependencies wired")
        XCTAssertTrue(true)
    }
}
