import SwiftUI
import SwiftData

/// P2.8 下载中心页：进行中 / 已完成 / 失败 列表，支持暂停/继续/删除与清理。
/// P5.2 无障碍：整行合并朗读（文件名 / 状态 / 进度）；进度条本身对 VoiceOver 隐藏，避免重复播报。
// iOS 17 SDK 的 `View` 协议本身不带 `@MainActor`（Xcode 16 / iOS 18 SDK 才加），
// 而本视图要访问 `@MainActor` 的 ViewModel 与工厂方法；显式标注可避免
// "main actor-isolated property ... can not be referenced from a non-isolated context"，
// 同时与后续 SDK 的默认行为一致。
@MainActor
struct DownloadView: View {
    let manager: DownloadManager
    @State private var vm: DownloadViewModel

    init(manager: DownloadManager) {
        self.manager = manager
        _vm = State(initialValue: DownloadViewModel(manager: manager))
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.records.isEmpty {
                    ContentUnavailableView("无下载任务", systemImage: "arrow.down.circle")
                }
                ForEach(vm.records) { record in
                    DownloadRow(record: record) {
                        vm.pause(record)
                    } resume: {
                        vm.resume(record)
                    } remove: {
                        vm.remove(record)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(A11yLabels.download(record.fileName,
                                                            state: record.state,
                                                            progress: record.progress))
                }
                .onDelete { indices in
                    indices.forEach { vm.remove(vm.records[$0]) }
                }
            }
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清理完成") { vm.clearCompleted() }
                        .accessibilityHint("删除所有已完成的下载记录")
                }
            }
            .task { vm.refresh() }
        }
    }
}

private struct DownloadRow: View {
    let record: DownloadRecord
    let pause: () -> Void
    let resume: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack {
                Text(record.fileName)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                stateBadge
            }
            ProgressView(value: record.progress)
                .accessibilityHidden(true)
            HStack(spacing: Spacing.m) {
                switch record.state {
                case .downloading, .queued:
                    Button("暂停", action: pause)
                        .accessibilityHint("暂停该下载任务")
                case .paused, .failed:
                    Button("继续", action: resume)
                        .accessibilityHint("从断点继续该下载任务")
                case .completed:
                    EmptyView()
                }
                Spacer()
                if record.state == .failed, let err = record.error {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Palette.danger)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private var stateBadge: some View {
        Text(A11yLabels.downloadState(record.state))
            .font(.footnote)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch record.state {
        case .queued:      return Palette.secondaryText
        case .downloading: return Palette.accent
        case .paused:      return Palette.warning
        case .completed:   return Palette.success
        case .failed:      return Palette.danger
        }
    }
}
