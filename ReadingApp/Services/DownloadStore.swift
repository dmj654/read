import Foundation
import SwiftData

/// P2.2 下载记录仓储：SwiftData 增删改查 + 按状态过滤 + 清理。
final class DownloadStore {
    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func all() throws -> [DownloadRecord] {
        try context.fetch(FetchDescriptor<DownloadRecord>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func byState(_ state: DownloadState) throws -> [DownloadRecord] {
        try context.fetch(FetchDescriptor<DownloadRecord>(
            predicate: #Predicate { $0.stateRaw == state.rawValue }
        ))
    }

    func byID(_ id: String) throws -> DownloadRecord? {
        try context.fetch(FetchDescriptor<DownloadRecord>(predicate: #Predicate { $0.id == id })).first
    }

    @discardableResult
    func insert(_ record: DownloadRecord) throws -> DownloadRecord {
        context.insert(record)
        try context.save()
        return record
    }

    func update(_ record: DownloadRecord) throws {
        record.updatedAt = .now
        try context.save()
    }

    func delete(_ record: DownloadRecord) throws {
        context.delete(record)
        try context.save()
    }

    /// 清理全部已完成记录（含落盘文件由调用方负责；此处仅清元数据）。
    func clearCompleted() throws {
        for record in try byState(.completed) { context.delete(record) }
        try context.save()
    }
}
