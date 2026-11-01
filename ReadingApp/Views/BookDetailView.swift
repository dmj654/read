import SwiftUI
import SwiftData

/// P1.3/P1.9 书详情页：抓取 BookInfo，提供「加入书架」与「阅读」入口。
struct BookDetailView: View {
    let result: SearchResult
    let repository: SourceRepository
    @State private var vm: BookDetailViewModel?

    init(result: SearchResult, repository: SourceRepository) {
        self.result = result
        self.repository = repository
    }

    var body: some View {
        Group {
            if let vm {
                DetailBody(vm: vm, repository: repository)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(result.title)
        .task { await buildVM() }
    }

    private func buildVM() async {
        guard let source = try? repository.sourceByID(result.sourceID) else { return }
        let store = BookshelfStore(context: PersistenceController.shared.context)
        let detailVM = BookDetailViewModel(bookshelf: store, source: source, bookURL: result.bookURL)
        await detailVM.load()
        vm = detailVM
    }
}

private struct DetailBody: View {
    let vm: BookDetailViewModel
    let repository: SourceRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if vm.isLoading {
                    ProgressView("加载中…")
                        .accessibilityLabel("正在加载书籍详情")
                }
                Text(vm.info?.title ?? "—")
                    .font(.title).bold()
                    .accessibilityAddTraits(.isHeader)
                if let author = vm.info?.author {
                    Text("作者：\(author)")
                        .foregroundStyle(Palette.secondaryText)
                }
                if let intro = vm.info?.intro {
                    Text(intro)
                        .font(.body)
                }
                if let cover = vm.info?.coverURL, URL(string: cover) != nil {
                    AsyncImage(url: URL(string: cover)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(maxHeight: 200)
                    .accessibilityLabel("封面")
                }
                Button {
                    vm.addToShelf()
                } label: {
                    Label("加入书架", systemImage: "books.vertical.fill")
                }
                .disabled(vm.savedBook != nil)
                .accessibilityHint(vm.savedBook != nil ? "该书已在书架中" : "把这本书加入本地书架")
                if vm.savedBook != nil {
                    Label("已加入书架", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                    if vm.source.type == .comic {
                        // P3：漫画走专用漫画阅读器（在线抓取图片页），复用 P2 下载底座做图片页缓存。
                        let cache = ComicPageCacheService.production()
                        NavigationLink("开始观看") {
                            ComicReaderView(viewModel: ComicReaderViewModel(
                                loadSource: .online(source: vm.source, chapterURL: vm.bookURL,
                                                    downloader: cache, service: ComicSourceService()),
                                book: vm.savedBook
                            ), downloader: cache)
                        }
                        .accessibilityHint("进入漫画阅读器")
                    } else {
                        NavigationLink("开始阅读") { ReaderView(source: vm.source, bookURL: vm.bookURL) }
                            .accessibilityHint("进入小说阅读器")
                    }
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
