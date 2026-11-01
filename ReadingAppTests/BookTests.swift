import XCTest
import SwiftData
@testable import ReadingApp

/// P0.5 Book 模型测试：验证基础字段、枚举、进度与可选字段持久化、唯一约束。
final class BookTests: XCTestCase {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Book.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 插入并取回：验证基础字段、枚举与进度持久化。
    func testInsertAndFetch() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let book = Book(
            title: "示例书名", author: "示例作者", type: .novel,
            sourceID: "src-1", progress: 0.42
        )
        context.insert(book)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Book>())
        let result = try XCTUnwrap(all.first)
        XCTAssertEqual(result.title, "示例书名")
        XCTAssertEqual(result.type, .novel)
        XCTAssertEqual(result.sourceID, "src-1")
        XCTAssertEqual(result.progress, 0.42, accuracy: 0.0001)
    }

    /// 漫画书与可选字段占位：验证 type=.comic、format/pageCount 及默认进度。
    func testComicBookStub() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let comic = Book(title: "示例漫画", type: .comic, format: "cbz", pageCount: 28)
        context.insert(comic)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Book>())
        let result = try XCTUnwrap(all.first)
        XCTAssertEqual(result.type, .comic)
        XCTAssertEqual(result.format, "cbz")
        XCTAssertEqual(result.pageCount, 28)
        XCTAssertEqual(result.progress, 0)
        XCTAssertNil(result.sourceID)
    }

    /// 唯一 id 约束：重复 id 插入应使 save 抛错。
    func testUniqueIdConstraint() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Book(id: "dup", title: "A"))
        try context.save()
        context.insert(Book(id: "dup", title: "B"))
        XCTAssertThrowsError(try context.save())
    }
}
