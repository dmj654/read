import SwiftUI
import SwiftData

// MARK: - P5.1 根导航：自适应（iPhone TabView / iPad NavigationSplitView）

/// 顶层分区：iPhone 走底部标签，iPad 走侧边栏多列。
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case shelf
    case discover
    case sources
    case downloads
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf: return "书架"
        case .discover: return "发现"
        case .sources: return "书源"
        case .downloads: return "下载"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: return "books.vertical"
        case .discover: return "magnifyingglass"
        case .sources: return "server.rack"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }
}

/// P5.1 根视图：按宽度类切换布局，复用 P0 底座与 P2 共享下载中心。
///
/// - 紧凑宽度（iPhone 竖屏 / 分屏窄栏）→ `TabView` 底部五标签。
/// - 常规宽度（iPad 全屏 / iPhone 横屏）→ `NavigationSplitView` 侧边栏 + 详情多列。
///
/// 两种布局共享同一状态源（`selection`）与同一批子视图，避免 iPad 与 iPhone 各自维护一套导航。
// iOS 17 SDK 的 `View` 协议本身不带 `@MainActor`（Xcode 16 / iOS 18 SDK 才加），
// 而本视图要访问 `@MainActor` 的 ViewModel 与工厂方法；显式标注可避免
// "main actor-isolated property ... can not be referenced from a non-isolated context"，
// 同时与后续 SDK 的默认行为一致。
@MainActor
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selection: AppSection = .shelf
    @State private var repository: SourceRepository
    @State private var bookshelfStore: BookshelfStore
    @State private var downloadManager: DownloadManager

    init() {
        let ctx = PersistenceController.shared.context
        _repository = State(initialValue: SourceRepository(context: ctx))
        _bookshelfStore = State(initialValue: BookshelfStore(context: ctx))
        _downloadManager = State(initialValue: AppDownloadCenter.manager)
    }

    private var mode: LayoutMode {
        LayoutResolver.mode(horizontalCompact: sizeClass == .compact)
    }

    var body: some View {
        Group {
            switch mode {
            case .tabs:
                tabLayout
            case .split:
                splitLayout
            }
        }
    }

    // MARK: 紧凑宽度：底部标签

    private var tabLayout: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                destination(for: section)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
                    .accessibilityLabel(section.title)
            }
        }
    }

    // MARK: 常规宽度：侧边栏 + 详情

    private var splitLayout: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: splitSelection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .accessibilityLabel(section.title)
            }
            .navigationTitle("开源阅读")
            .listStyle(.sidebar)
        } detail: {
            destination(for: selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// `List` 的多选绑定是 `AppSection?`，与 `TabView` 用的非可选状态做桥接。
    private var splitSelection: Binding<AppSection?> {
        Binding(
            get: { selection },
            set: { if let new = $0 { selection = new } }
        )
    }

    // MARK: 分区 → 具体页面

    @ViewBuilder
    private func destination(for section: AppSection) -> some View {
        switch section {
        case .shelf:
            BookshelfView(store: bookshelfStore)
        case .discover:
            SearchView(repository: repository)
        case .sources:
            SourceManagementView(repository: repository)
        case .downloads:
            DownloadView(manager: downloadManager)
        case .settings:
            SettingsView()
        }
    }
}
