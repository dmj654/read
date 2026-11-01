import Foundation

/// P2.3 下载队列：纯逻辑并发控制（不依赖网络 / SwiftData，便于单测）。
/// 维护「进行中(active)」与「排队(pending)」，按并发上限拉起下一个。
struct DownloadQueue {
    var maxConcurrent: Int
    private(set) var active: [String] = []
    private(set) var pending: [String] = []

    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = max(maxConcurrent, 1)
    }

    /// 入队：有空槽立即激活返回 true，否则进入排队返回 false。
    mutating func enqueue(_ id: String) -> Bool {
        if active.count < maxConcurrent {
            active.append(id)
            return true
        }
        pending.append(id)
        return false
    }

    /// 重新入队（暂停/失败后恢复下载）。
    mutating func requeue(_ id: String) -> Bool {
        if active.count < maxConcurrent {
            active.append(id)
            return true
        }
        pending.append(id)
        return false
    }

    /// 任务结束（完成/失败/暂停取消）：释放其活动槽并拉起下一个排队任务。
    mutating func complete(_ id: String) -> String? {
        active.removeAll { $0 == id }
        return pullNext()
    }

    /// 整体移除（用户删除）：释放槽并拉起下一个。
    mutating func cancel(_ id: String) -> String? {
        active.removeAll { $0 == id }
        pending.removeAll { $0 == id }
        return pullNext()
    }

    private mutating func pullNext() -> String? {
        if active.count < maxConcurrent, let next = pending.first {
            pending.removeFirst()
            active.append(next)
            return next
        }
        return nil
    }
}
