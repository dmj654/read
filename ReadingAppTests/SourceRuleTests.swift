import XCTest
import SwiftData
@testable import ReadingApp

/// P0.3 SourceRule 模型测试：验证 SwiftData 持久化、枚举存储、可选字段、唯一约束。
final class SourceRuleTests: XCTestCase {

    /// 创建仅存于内存的 ModelContainer，保证测试间相互隔离。
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([SourceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 插入并取回：验证基础字段与枚举持久化。
    func testInsertAndFetch() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let rule = SourceRule(
            name: "测试书源", type: .novel, priority: 9,
            searchUrl: "https://example.com/search?q={{key}}",
            ruleSearch: "//div[@class='book']",
            ruleBookInfo: "##author", ruleToc: "##toc", ruleContent: "##content"
        )
        context.insert(rule)
        try context.save()

        let descriptor = FetchDescriptor<SourceRule>(
            predicate: #Predicate { $0.name == "测试书源" }
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        let result = try XCTUnwrap(fetched.first)
        XCTAssertEqual(result.name, "测试书源")
        XCTAssertEqual(result.type, .novel)
        XCTAssertEqual(result.priority, 9)
        XCTAssertEqual(result.searchUrl, "https://example.com/search?q={{key}}")
    }

    /// 漫画专属可选字段：验证可选 String 持久化与通用规则默认空串。
    func testComicOptionalFieldsRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let comic = SourceRule(
            name: "测试漫源", type: .comic, priority: 7,
            imageListRule: "//img", imageUrlRule: "@src",
            nextPageRule: "next", adPageFilter: "ad"
        )
        context.insert(comic)
        try context.save()

        let all = try context.fetch(FetchDescriptor<SourceRule>())
        let result = try XCTUnwrap(all.first)
        XCTAssertEqual(result.type, .comic)
        XCTAssertEqual(result.imageListRule, "//img")
        XCTAssertEqual(result.imageUrlRule, "@src")
        XCTAssertEqual(result.nextPageRule, "next")
        XCTAssertEqual(result.adPageFilter, "ad")
        XCTAssertEqual(result.ruleSearch, "")   // 通用规则未赋值 → 默认空串
    }

    /// 默认书源：验证 type 默认 .novel、enabled 默认 true、漫画字段默认 nil。
    func testNovelDefaults() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let novel = SourceRule(name: "默认书源")
        context.insert(novel)
        try context.save()

        let all = try context.fetch(FetchDescriptor<SourceRule>())
        let result = try XCTUnwrap(all.first)
        XCTAssertEqual(result.type, .novel)
        XCTAssertTrue(result.enabled)
        XCTAssertNil(result.imageListRule)       // 漫画字段默认 nil
    }

    /// 唯一 id 约束：重复 id 插入应使 save 抛错（数据完整性）。
    func testUniqueIdConstraint() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(SourceRule(id: "dup-id", name: "A"))
        try context.save()
        context.insert(SourceRule(id: "dup-id", name: "B"))
        XCTAssertThrowsError(try context.save())
    }
}
