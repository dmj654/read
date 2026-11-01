import SwiftUI

/// P4.6 统一设置页（双体系共用）：同步入口、数据说明与关于。
/// P5.4 上架准备：补充隐私说明与开源许可入口，形成可审核的合规信息闭环。
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("同步") {
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        Label("WebDAV / NAS 同步", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                }

                Section("数据") {
                    LabeledContent("存储", value: "本地优先（SwiftData）")
                    LabeledContent("默认同步范围", value: "进度 · 书源 · 设置")
                    LabeledContent("全量文件同步", value: "默认关闭")
                }

                Section("隐私与开源") {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("隐私说明", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        OpenSourceLicensesView()
                    } label: {
                        Label("开源许可", systemImage: "doc.text")
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("定位", value: "纯本地阅读工具 · 不含任何内置内容")
                    LabeledContent("最低系统", value: "iOS 17")
                }
            }
            .navigationTitle("设置")
        }
    }
}
