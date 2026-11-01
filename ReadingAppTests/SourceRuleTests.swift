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

    /// 唯一 id 约束：同一个 id 不能被写入两条记录（数据完整性）。
    ///
    /// 这里**不**断言「重复插入会让 save 抛错」。`@Attribute(.unique)` 的行为随系统版本变化：
    /// iOS 18 上 save 会抛错，iOS 26 上改成直接 upsert（后写覆盖前写，不报错）。
    /// 两者都是合法实现，把测试绑在某一种上只会让用例随运行时版本翻脸。
    /// 真正需要守住的不变量只有一个：库里这个 id 只能有一条。
    func testUniqueIdConstraint() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let dupID = "dup-id"

        context.insert(SourceRule(id: dupID, name: "A"))
        try context.save()

        context.insert(SourceRule(id: dupID, name: "B"))
        do {
            try context.save()
        } catch {
            // 旧版 SwiftData 会因唯一约束冲突抛错；回滚掉这条待写入的记录，
            // 否则后续 fetch 会把未落库的对象也带出来，掩盖真实结果。
            context.rollback()
        }

        let all = try context.fetch(FetchDescriptor<SourceRule>())
        XCTAssertEqual(all.filter { $0.id == dupID }.count, 1,
                       "唯一约束失效：同一个 id 出现了多条记录")
    }
}
