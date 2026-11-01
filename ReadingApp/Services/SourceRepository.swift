import Foundation
import SwiftData

/// P1.1 书源仓储：复用 PersistenceController 与 SourceImporter，提供书源 CRUD / 导入 / 启停 / 优先级排序。
final class SourceRepository {
    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    /// 全部书源（按优先级降序）。
    func allSources() throws -> [SourceRule] {
        try context.fetch(FetchDescriptor<SourceRule>(sortBy: [SortDescriptor(\.priority, order: .reverse)]))
    }

    /// 仅启用书源（按优先级降序）。
    func enabledSources() throws -> [SourceRule] {
        try context.fetch(FetchDescriptor<SourceRule>(
            predicate: #Predicate { $0.enabled },
            sortBy: [SortDescriptor(\.priority, order: .reverse)]
        ))
    }

    func sourceByID(_ id: String) throws -> SourceRule? {
        try context.fetch(FetchDescriptor<SourceRule>(predicate: #Predicate { $0.id == id })).first
    }

    /// 导入 Legado 源 JSON（复用 P0.19 SourceImporter），并落库。
    @discardableResult
    func importSource(json: Data) throws -> SourceRule {
        let rule = try SourceImporter.import(json: json)
        context.insert(rule)
        try context.save()
        return rule
    }

    func add(_ rule: SourceRule) throws {
        context.insert(rule)
        try context.save()
    }

    func toggle(_ rule: SourceRule, enabled: Bool) throws {
        rule.enabled = enabled
        try context.save()
    }

    func setPriority(_ rule: SourceRule, priority: Int) throws {
        rule.priority = priority
        try context.save()
    }

    func delete(_ rule: SourceRule) throws {
        context.delete(rule)
        try context.save()
    }
}
