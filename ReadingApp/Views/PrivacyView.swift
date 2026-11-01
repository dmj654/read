import SwiftUI

/// P5.4 隐私声明页：零采集、零上报、无三方 SDK 的可见承诺（与 `PRIVACY.md` 一致）。
///
/// 上架审核要点：本 App 为纯本地工具，仅在你主动配置书源 / 同步时才会发起网络请求。
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("数据采集") {
                LabeledContent("账号", value: "无需注册登录")
                LabeledContent("行为统计", value: "不采集")
                LabeledContent("崩溃上报", value: "不接入三方 SDK")
                LabeledContent("广告标识符", value: "不读取")
            }

            Section("数据存储") {
                Text("书架、阅读进度、书源规则、下载记录全部保存在本机（SwiftData / 文件系统），不上传任何服务器。")
                    .font(.footnote)
                Text("WebDAV / NAS 同步使用你自己填写的服务器地址，凭据保存在系统钥匙串（Keychain），仅用于你配置的同步。")
                    .font(.footnote)
            }

            Section("网络访问") {
                Text("仅在以下场景发起网络请求：搜索书源、加载章节正文或漫画图片页、下载离线内容、你手动触发的同步。")
                    .font(.footnote)
                Text("请求直接发往书源或同步服务器，不经过任何中间代理。")
                    .font(.footnote)
            }

            Section("内容来源") {
                Text("本 App 不内置任何书籍内容，全部内容由你导入或添加的书源规则获取，版权归原站点与作者所有。")
                    .font(.footnote)
                Text("请遵守内容提供方的服务条款与当地法律法规，仅将本工具用于个人合法的阅读用途。")
                    .font(.footnote)
            }
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// P5.4 开源许可页：列出运行时依赖的第三方库及其许可类型。
struct OpenSourceLicensesView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let license: String
        let usage: String
    }

    private let entries: [Entry] = [
        .init(name: "Kanna", license: "MIT", usage: "XPath / CSS 选择器解析"),
        .init(name: "ZIPFoundation", license: "MIT", usage: "CBZ / ZIP 漫画容器解包"),
        .init(name: "PDFKit", license: "Apple 系统框架", usage: "PDF 漫画渲染"),
        .init(name: "SwiftData", license: "Apple 系统框架", usage: "本地数据持久化")
    ]

    var body: some View {
        List {
            Section("第三方组件") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.body)
                        Text("\(entry.license) · \(entry.usage)")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section("本项目") {
                Text("App 本体以 MIT 许可开源，书源规则格式兼容 Legado 生态。")
                    .font(.footnote)
            }
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}
