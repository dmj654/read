import Foundation
import SwiftData

/// P2.6 下载管理器（主线程 Actor）：编排 仓储 + 队列 + 执行器，响应下载事件推进状态机。
///
/// 事件来源：生产环境为 `BackgroundDownloadCoordinator`（后台会话代理回调经主线程派发）；
/// 测试环境为 `StubDownloadRunner`（直接注入 `handle(_:)`）。
@MainActor
final class DownloadManager {
    private let store: DownloadStore
    private let runner: DownloadRunner
    private var queue: DownloadQueue

    init(store: DownloadStore, runner: DownloadRunner, maxConcurrent: Int = 3) {
        self.store = store
        self.runner = runner
        self.queue = DownloadQueue(maxConcurrent: maxConcurrent)
        runner.onEvent = { [weak self] event in
            // 弱捕获的 `self` 本质是可变引用，若直接在内层并发闭包（`Task`）里引用，
            // Swift 5.10 会报 "reference to captured var 'self' in concurrently-executing code"。
            // 先解包成不可变局部变量，再交给主线程任务。
            guard let strongSelf = self else { return }
            Task { @MainActor in strongSelf.handle(event) }
        }
    }

    // MARK: 公开 API

    @discardableResult
    func enqueue(url: String, fileName: String, bookID: String? = nil, sourceID: String? = nil) throws -> DownloadRecord {
        // `DownloadRecord.init` 的形参顺序是 (id, bookID, sourceID, url, fileName, …)，
        // 必须按声明顺序传参。
        let record = DownloadRecord(bookID: bookID, sourceID: sourceID, url: url, fileName: fileName)
        try store.insert(record)
        if queue.enqueue(record.id) {
            record.state = .downloading
            try store.update(record)
            runner.start(recordID: record.id, url: url, resumeData: nil)
        } else {
            record.state = .queued
            try store.update(record)
        }
        return record
    }

    func records() throws -> [DownloadRecord] { try store.all() }

    func clearCompleted() throws { try store.clearCompleted() }

    func pause(_ record: DownloadRecord) {
        record.state = .paused
        try? store.update(record)
        runner.cancel(recordID: record.id)   // 续传凭证经随后的 .failed 事件回收
    }

    func resume(_ record: DownloadRecord) {
        guard record.state == .paused || record.state == .failed else { return }
        if queue.requeue(record.id) {
            record.state = .downloading
            try? store.update(record)
            runner.start(recordID: record.id, url: record.url, resumeData: record.resumeData)
        } else {
            record.state = .queued
            try? store.update(record)
        }
    }

    func cancel(_ record: DownloadRecord) {
        runner.cancel(recordID: record.id)
        if let next = queue.cancel(record.id) { startRecord(next) }
        try? store.delete(record)
    }

    // MARK: 事件处理（internal 供测试直接注入）

    func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let id, let written, let total):
            guard let record = try? store.byID(id) else { return }
            record.bytesWritten = written
            record.totalBytes = total
            record.progress = total > 0 ? min(1, Double(written) / Double(total)) : record.progress
            if record.state != .downloading { record.state = .downloading }
            try? store.update(record)
        case .finished(let id, _):
            guard let record = try? store.byID(id) else { return }
            record.state = .completed
            record.progress = 1
            record.error = nil
            try? store.update(record)
            startNext(after: id)
        case .failed(let id, let message, let resume):
            guard let record = try? store.byID(id) else { return }
            if let resume { record.resumeData = resume }
            if record.state != .paused { record.state = .failed }
            record.error = message
            try? store.update(record)
            startNext(after: id)
        }
    }

    // MARK: 内部

    private func startNext(after id: String) {
        guard let next = queue.complete(id) else { return }
        startRecord(next)
    }

    private func startRecord(_ id: String) {
        guard let record = try? store.byID(id) else { return }
        record.state = .downloading
        try? store.update(record)
        runner.start(recordID: id, url: record.url, resumeData: record.resumeData)
    }
}
