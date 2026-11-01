import SwiftUI

@main
struct ReadingAppApp: App {
    /// 桥接 UIKit 应用生命周期，用于接收后台 URL 会话唤醒回调（P2.6）。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
