import SwiftUI
import SwiftData

/// P1.4/P1.9 书架页：双视图（网格封面墙 / 列表），支持搜索过滤。
/// P5.2 无障碍：单元格合并朗读（书名 / 类型 / 进度）；封面尺寸随 Dynamic Type 缩放。
struct BookshelfView: View {
    @State private var vm: BookshelfViewModel

    init(store: BookshelfStore) { _vm = State(initialValue: BookshelfViewModel(store: store)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s) {
                Picker("视图", selection: $vm.viewMode) {
                    Text("网格").tag(BookshelfViewMode.grid)
                    Text("列表").tag(BookshelfViewMode.list)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.m)
                .accessibilityLabel("书架显示方式")

                TextField("搜索", text: $vm.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, Spacing.m)
                    .accessibilityLabel("在书架中搜索")

                if vm.filtered.isEmpty {
                    Spacer()
                    ContentUnavailableView("书架为空", systemImage: "books.vertical",
                                           description: Text("去「发现」搜索并加入书架"))
                    Spacer()
                } else if vm.viewMode == .grid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: Spacing.m) {
                            ForEach(vm.filtered) { book in
                                NavigationLink {
                                    ReaderRouterView(book: book)
                                } label: {
                                    BookCell(book: book)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(A11yLabels.book(book.title, type: book.type, progress: book.progress))
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                        .padding(.horizontal, Spacing.m)
                    }
                } else {
                    List(vm.filtered) { book in
                        NavigationLink {
                            ReaderRouterView(book: book)
                        } label: {
                            BookRow(book: book)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(A11yLabels.book(book.title, type: book.type, progress: book.progress))
                    }
                }
            }
            .navigationTitle("书架")
            .task { vm.load() }
        }
    }
}

// MARK: - 网格单元格

private struct BookCell: View {
    let book: Book

    /// 封面尺寸随 Dynamic Type 放大，避免大字号下封面与文字比例失衡。
    @ScaledMetric(relativeTo: .caption) private var coverWidth: CGFloat = 100

    private var coverHeight: CGFloat { coverWidth * 1.4 }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            cover
            Text(book.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            typeBadge
            ProgressView(value: book.progress)
                .frame(width: coverWidth)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let urlString = book.coverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Palette.surface
            }
            .frame(width: coverWidth, height: coverHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.surface)
                .frame(width: coverWidth, height: coverHeight)
                .overlay {
                    Image(systemName: book.type == .comic ? "photo.on.rectangle" : "book.closed")
                        .foregroundStyle(Palette.secondaryText)
                }
        }
    }

    @ViewBuilder
    private var typeBadge: some View {
        if book.type == .comic {
            Text("漫")
                .font(.caption2).bold()
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 1)
                .background(Palette.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 列表行

private struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: Spacing.s) {
            if book.type == .comic {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .lineLimit(2)
                Text(book.author)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            ProgressView(value: book.progress)
                .frame(width: 60)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}
