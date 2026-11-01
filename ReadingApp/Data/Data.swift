import Foundation
import SwiftData

/// 数据层统一入口：生产容器 + 内存容器（测试隔离）。
///
/// 生产环境使用持久化容器；测试环境使用 `inMemory()` 获取相互隔离的内存容器。
final class PersistenceController {

    static let shared = PersistenceController()

    let container: ModelContainer

    /// 全局共享上下文。
    ///
    /// 这里**不用** `container.mainContext`：它被 SwiftData 标记为 `@MainActor` 隔离，
    /// 一旦从非隔离上下文（SwiftUI 的 `View.init`、`@ViewBuilder` 计算属性、
    /// 普通 `async` 方法）引用就会编译失败；若反过来给访问器加 `@MainActor`，
    /// 又会把上面三类调用点全部污染，形成隔离级联。
    ///
    /// 本工程未使用 `@Query` / `.modelContainer(_:)`，全部数据访问都经由本属性注入给
    /// `SourceRepository` / `BookshelfStore` / `DownloadStore` / `SyncViewModel` 等仓储，
    /// 因此初始化时自建一个上下文与 `mainContext` 语义等价，且不引入隔离传播。
    let context: ModelContext

    private init() {
        do {
            let schema = Schema([SourceRule.self, AppSettings.self, Book.self, DownloadRecord.self, SyncConfig.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema)]
            )
            self.container = container
            self.context = ModelContext(container)
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

    /// 保存共享上下文；无变更时直接返回，错误向外抛出由调用方处理。
    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
