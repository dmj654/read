import Foundation

/// P2.5 下载事件（全部成员 Sendable，便于跨线程传递）。
enum DownloadEvent: Sendable {
    case progress(recordID: String, bytesWritten: Int64, totalBytes: Int64)
    case finished(recordID: String, finalURL: URL)
    case failed(recordID: String, errorMessage: String, resumeData: Data?)
}

/// 下载执行协议：管理器的可注入依赖，测试用桩替换。
/// 约束为 `AnyObject`：管理器持有 `let runner` 并需要改写其 `onEvent` 回调，
/// 只有引用类型语义才成立（值类型无法通过 `let` 常量赋值）。
protocol DownloadRunner: AnyObject {
    var onEvent: (@Sendable (DownloadEvent) -> Void)? { get set }
    func start(recordID: String, url: String, resumeData: Data?)
    func cancel(recordID: String)
}

/// P2.5 后台下载协调器：持有后台 `URLSession`，将代理回调翻译为 `DownloadEvent`。
///
/// 设计要点：后台会话是「统一管理网络层」原则下**唯一**的例外——系统要求下载类后台会话
/// 独立于前台 `NetworkService`（P0.7）。前台请求仍全部走 `NetworkService`。
/// `didFinishDownloadingTo` 内必须同步完成文件搬移（系统随后删除临时文件），因此由协调器
/// 直接借助注入的 `FileStoring` 落盘，再向上汇报 `finished`。
final class BackgroundDownloadCoordinator: NSObject, URLSessionDownloadDelegate, DownloadRunner {
    /// 后台会话固定标识（与 AppDelegate 回调匹配）。
    static let identifier = "com.example.ReadingApp.download"

    var onEvent: (@Sendable (DownloadEvent) -> Void)?
    /// 后台会话在 App 被唤醒交付完所有事件后，由系统回调的结束处理器（AppDelegate 注入）。
    var backgroundCompletionHandler: (() -> Void)?
    private let fileStore: FileStoring
    /// 后台会话必须以 `self` 作为 delegate，而 `self` 只有在 `super.init()` 之后才可用；
    /// 同时 `let` 存储属性又必须早于 `super.init()` 初始化——两者不可兼得，
    /// 因此声明为 `var` + 隐式解包，在 `super.init()` 之后立即赋值（生命周期内仅赋值一次）。
    private var session: URLSession!
    private let lock = NSLock()
    private var fileNames: [String: String] = [:]   // recordID -> fileName

    // 默认参数里不能用协变 `Self`（error: covariant 'Self' type cannot be referenced
    // from a default argument expression），改为显式写死类型名。
    init(fileStore: FileStoring, identifier: String = BackgroundDownloadCoordinator.identifier) {
        self.fileStore = fileStore
        super.init()
        let config = NetworkSessionFactory.backgroundConfig(forIdentifier: identifier)
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: DownloadRunner

    func start(recordID: String, url: String, resumeData: Data?) {
        lock.lock(); defer { lock.unlock() }
        fileNames[recordID] = fileNames[recordID] ?? recordID

        guard let target = URL(string: url) else {
            onEvent?(.failed(recordID: recordID, errorMessage: "invalid url", resumeData: nil))
            return
        }
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: target)
        }
        task.taskDescription = recordID
        task.resume()
    }

    func cancel(recordID: String) {
        // `getAllTasks` 交付的是 `[URLSessionTask]`，只有向下转型为
        // `URLSessionDownloadTask` 才有 `cancel(byProducingResumeData:)`。
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == recordID {
                (task as? URLSessionDownloadTask)?.cancel(byProducingResumeData: { _ in })
            }
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                   didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                   totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        onEvent?(.progress(recordID: id, bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                   didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        lock.lock(); let fileName = fileNames[id] ?? id; lock.unlock()
        do {
            let final = try fileStore.persist(from: location, fileName: fileName)
            onEvent?(.finished(recordID: id, finalURL: final))
        } catch {
            onEvent?(.failed(recordID: id, errorMessage: error.localizedDescription, resumeData: nil))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 成功下载时 didFinishDownloadingTo 已先触发 finished；此处仅在失败时回调（error 非 nil）。
        guard let id = task.taskDescription, let error else { return }
        // 续传凭证在 NSError.userInfo 里以固定字符串键存放；`NSURLSessionDownloadTaskResumeDataKey`
        // 并非 Swift 可见的常量，直接用其文档约定的字面量键。
        let resume = (error as NSError).userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
        onEvent?(.failed(recordID: id, errorMessage: error.localizedDescription, resumeData: resume))
    }

    // MARK: URLSessionDelegate（后台会话结束事件）

    /// 后台会话交付完所有事件后由系统回调，此处调用 AppDelegate 注入的结束处理器，
    /// 告知系统可以重新挂起 App。调用后清空，避免重复调用引发崩溃。
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }
}

extension BackgroundDownloadCoordinator {
    /// 重新关联（唤醒）后台会话。进程冷启动或被后台下载事件唤醒时调用，
    /// 确保 `shared` 单例已初始化并持有有效的后台 `URLSession` 实例。
    /// 由于后台会话标识符固定，重复创建返回的是系统层面的同一会话，
    /// 未完成的下载会在新会话内自动续传并由代理回调向上汇报。
    @discardableResult
    static func reconnect() -> BackgroundDownloadCoordinator {
        shared
    }
}

extension BackgroundDownloadCoordinator {
    /// 应用级共享后台下载协调器（进程生命周期内常驻，保证后台任务可续传）。
    static let shared = BackgroundDownloadCoordinator(fileStore: DownloadFileManager.production)
}
