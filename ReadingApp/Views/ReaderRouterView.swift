import SwiftUI

/// P4.5 双体系收口：书架统一入口，按 `Book.type` 分派到小说或漫画阅读器。
///
/// 小说 → `ReaderView`；漫画 → `ComicReaderView`（在线抓取图片页 + 生产缓存）。
/// 缺书源/详情链接时给出可读的降级提示，而非崩溃或空屏。
// iOS 17 SDK 的 `View` 协议本身不带 `@MainActor`（Xcode 16 / iOS 18 SDK 才加），
// 而本视图要访问 `@MainActor` 的 ViewModel 与工厂方法；显式标注可避免
// "main actor-isolated property ... can not be referenced from a non-isolated context"，
// 同时与后续 SDK 的默认行为一致。
@MainActor
struct ReaderRouterView: View {
    let book: Book

    var body: some View {
        Group {
            switch book.type {
            case .novel:
                novelReader
            case .comic:
                comicReader
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var novelReader: some View {
        if let url = book.bookURL, let source = resolveSource() {
            ReaderView(source: source, bookURL: url)
        } else {
            ReaderFallback(message: "缺少书源或详情链接，无法打开该书。")
        }
    }

    @ViewBuilder
    private var comicReader: some View {
        if let url = book.bookURL, let source = resolveSource() {
            let cache = ComicPageCacheService.production()
            ComicReaderView(
                viewModel: ComicReaderViewModel(
                    loadSource: .online(source: source, chapterURL: url,
                                        downloader: cache, service: ComicSourceService()),
                    book: book
                ),
                downloader: cache
            )
        } else {
            ReaderFallback(message: "缺少漫源或详情链接，无法打开该漫画。")
        }
    }

    private func resolveSource() -> SourceRule? {
        guard let id = book.sourceID else { return nil }
        let repository = SourceRepository(context: PersistenceController.shared.context)
        return try? repository.sourceByID(id)
    }
}

private struct ReaderFallback: View {
    let message: String
    var body: some View {
        ContentUnavailableView("无法打开", systemImage: "book.closed", description: Text(message))
    }
}
