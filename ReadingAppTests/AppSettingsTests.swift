import XCTest
import SwiftData
@testable import ReadingApp

/// P0.4 AppSettings 模型测试：验证同步策略默认值、枚举可序列化、单例加载。
final class AppSettingsTests: XCTestCase {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([AppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 默认构造：验证同步策略决策落地（关键）。
    func testDefaultSyncPolicy() {
        let s = AppSettings()
        XCTAssertEqual(s.syncMode, .metadata)
        XCTAssertFalse(s.fullFileSyncEnabled)
    }

    /// 枚举可序列化：为 P4 WebDAV 传输预备。
    func testSyncModeCodable() throws {
        let data = try JSONEncoder().encode(SyncMode.full)
        let decoded = try JSONDecoder().decode(SyncMode.self, from: data)
        XCTAssertEqual(decoded, .full)
    }

    /// 单例加载：首次创建默认，二次返回同一记录（不重复插入）。
    func testLoadOrCreateSingleton() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let first = try AppSettings.loadOrCreate(in: context)
        XCTAssertEqual(first.syncMode, .metadata)
        XCTAssertFalse(first.fullFileSyncEnabled)

        let second = try AppSettings.loadOrCreate(in: context)
        XCTAssertEqual(first.id, second.id)

        let all = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(all.count, 1)
    }
}
