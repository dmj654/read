import SwiftUI
import SwiftData

/// P4.6 WebDAV/NAS 同步设置页：服务器、账号、密码（Keychain）、目录、测试连接、立即同步。
// iOS 17 SDK 的 `View` 协议本身不带 `@MainActor`（Xcode 16 / iOS 18 SDK 才加），
// 而本视图要访问 `@MainActor` 的 ViewModel 与工厂方法；显式标注可避免
// "main actor-isolated property ... can not be referenced from a non-isolated context"，
// 同时与后续 SDK 的默认行为一致。
@MainActor
struct SyncSettingsView: View {
    @State private var vm: SyncViewModel

    init() { _vm = State(initialValue: SyncViewModel()) }

    var body: some View {
        Form {
            Section {
                TextField("服务器地址（https://…/webdav）", text: $vm.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("WebDAV 服务器地址")
                TextField("用户名", text: $vm.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("WebDAV 用户名")
                SecureField("密码（仅存 Keychain）", text: $vm.password)
                    .accessibilityLabel("WebDAV 密码")
                TextField("远端目录", text: $vm.directory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("远端同步目录")
            } header: {
                Text("WebDAV 服务器")
            } footer: {
                Text("兼容 Synology / QNAP / Nextcloud / 自建 NAS；域名需为 WebDAV 根路径。")
            }

            Section {
                Toggle("启动时自动同步", isOn: $vm.autoSync)
                Button {
                    Task { await vm.testConnection() }
                } label: {
                    Label("测试连接", systemImage: "network")
                }
                .disabled(!vm.canSubmit || vm.isBusy)

                Button {
                    Task { await vm.syncNow() }
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!vm.canSubmit || vm.isBusy)
            } footer: {
                statusFooter
            }

            Section("状态") {
                LabeledContent("最近同步",
                               value: vm.lastSyncAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "从未")
                LabeledContent("远端版本", value: "v\(vm.lastVersion)")
            }
        }
        .navigationTitle("同步")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch vm.status {
        case .idle:
            EmptyView()
        case .testing:
            Text("正在测试连接…")
        case .syncing:
            Text("正在同步…")
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
                .accessibilityLabel("同步成功：\(message)")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityLabel("同步失败：\(message)")
        }
    }
}
