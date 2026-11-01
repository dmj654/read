import Foundation
import SwiftData

/// 数据层统一入口：生产容器 + 内存容器（测试隔离）。
///
/// 生产环境使用持久化容器；测试环境使用 `inMemory()` 获取相互隔离的内存容器。
final class PersistenceController {

    static let shared = PersistenceController()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private init() {
        do {
            let schema = Schema([SourceRule.self, AppSettings.self, Book.self, DownloadRecord.self, SyncConfig.self])
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema)]
            )
        } catch {
            fatalError("PersistenceController 初始化失败: \(error)")
        }
    }

    /// 仅供测试：内存容器，用例间相互隔离。
    static func inMemory() throws -> ModelContainer {
        let schema = Schema([SourceRule.self, AppSettings.self, Book.self, DownloadRecord.self, SyncConfig.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 保存主上下文；无变更时直接返回，错误向外抛出由调用方处理。
    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
