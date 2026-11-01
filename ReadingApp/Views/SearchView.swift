import SwiftUI

/// P1.2/P1.9 发现（搜索）页：关键词 → 跨源结果列表 → 进入书详情。
/// P5.2 无障碍：结果行合并朗读书名与作者；搜索按钮提供明确的可用性反馈与提示。
struct SearchView: View {
    @State private var vm: SearchViewModel
    private let repository: SourceRepository

    init(repository: SourceRepository) {
        self.repository = repository
        _vm = State(initialValue: SearchViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    TextField("书名 / 作者", text: $vm.keyword)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { Task { await vm.search() } }
                        .accessibilityLabel("搜索关键词")
                    Button {
                        Task { await vm.search() }
                    } label: {
                        Text("搜索")
                    }
                    .disabled(vm.keyword.isEmpty || vm.isLoading)
                    .accessibilityHint("在全部书源中搜索该书")
                }
                .padding(.horizontal, Spacing.m)

                if vm.isLoading {
                    ProgressView("搜索中…")
                        .accessibilityLabel("正在搜索")
                }
                if let err = vm.error {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .padding(.horizontal, Spacing.m)
                        .accessibilityLabel("搜索出错：\(err)")
                }

                if vm.results.isEmpty && !vm.isLoading && !vm.keyword.isEmpty {
                    ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass",
                                           description: Text("换个关键词，或检查书源是否可用"))
                } else {
                    List(vm.results) { result in
                        NavigationLink {
                            BookDetailView(result: result, repository: repository)
                        } label: {
                            SearchRow(result: result)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(A11yLabels.searchResult(result.title, author: result.author))
                    }
                }
            }
            .navigationTitle("发现")
        }
    }
}

private struct SearchRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(result.title)
                .lineLimit(2)
            Spacer(minLength: Spacing.s)
            if let author = result.author {
                Text(author)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}
