import Foundation
import SwiftData

/// 下载单元状态机：排队 → 下载中 →（完成 | 失败 | 已暂停）。
enum DownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

/// P2.1 下载记录（SwiftData 实体）：小说章节 / 漫画图片页抽象为统一「下载单元」。
/// 落盘文件名与状态持久化，进程重启后可恢复队列（后台会话回调续传）。
@Model
final class DownloadRecord {
    @Attribute(.unique) var id: String
    var bookID: String?          // 关联 Book.id（本地单元可 nil）
    var sourceID: String?
    var url: String              // 下载单元 URL
    var fileName: String         // 落盘文件名（含扩展名）
    var stateRaw: String         // 以 String 存储，便于 #Predicate 过滤与轻量迁移
    var progress: Double         // 0...1
    var bytesWritten: Int64
    var totalBytes: Int64
    var resumeData: Data?        // 断点续传凭证（取消/失败后由系统返回）
    var error: String?
    var createdAt: Date
    var updatedAt: Date

    var state: DownloadState {
        get { DownloadState(rawValue: stateRaw) ?? .queued }
        set { stateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        bookID: String? = nil,
        sourceID: String? = nil,
        url: String,
        fileName: String,
        state: DownloadState = .queued,
        progress: Double = 0,
        bytesWritten: Int64 = 0,
        totalBytes: Int64 = 0,
        resumeData: Data? = nil,
        error: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.sourceID = sourceID
        self.url = url
        self.fileName = fileName
        self.stateRaw = state.rawValue
        self.progress = progress
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
        self.resumeData = resumeData
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
