import Foundation
import Observation
import SwiftData

/// P2.7 下载中心 ViewModel：暴露列表、过滤与暂停/继续/删除/清理动作（主线程 Actor）。
@MainActor
final class DownloadViewModel {
    private let manager: DownloadManager
    var records: [DownloadRecord] = []
    var filter: DownloadState? = nil

    init(manager: DownloadManager) { self.manager = manager }

    func refresh() {
        guard let all = try? manager.records() else { records = []; return }
        records = filter.map { f in all.filter { $0.state == f } } ?? all
    }

    func enqueue(url: String, fileName: String) {
        try? manager.enqueue(url: url, fileName: fileName)
        refresh()
    }

    func pause(_ record: DownloadRecord) { manager.pause(record); refresh() }
    func resume(_ record: DownloadRecord) { manager.resume(record); refresh() }
    func remove(_ record: DownloadRecord) { manager.cancel(record); refresh() }
    func clearCompleted() { try? manager.clearCompleted(); refresh() }
}
