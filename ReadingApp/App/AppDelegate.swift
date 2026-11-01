import UIKit

/// P2.6 后台 URL 会话回调桥接。
///
/// iOS 在以下两种情形会唤醒（或启动）App 并调用此回调：
/// 1. 后台下载任务完成、需要交付事件时；
/// 2. 进程被系统终止后，后台下载仍在继续，完成后系统重新拉起 App 交付事件。
///
/// 系统同时提供 `completionHandler`，必须**在后台会话交付完所有事件后**调用，
/// 否则系统会一直保持 App 活跃、浪费电量。我们把该 handler 写入
/// `BackgroundDownloadCoordinator.shared`，由其 `urlSessionDidFinishEvents` 在收尾时调用。
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        // 仅处理本应用登记的后台下载标识符；其它标识符（若有）忽略。
        guard identifier == BackgroundDownloadCoordinator.identifier else { return }
        // 确保单例已初始化（持有有效的后台会话），再写入结束处理器。
        BackgroundDownloadCoordinator.reconnect().backgroundCompletionHandler = completionHandler
    }
}
