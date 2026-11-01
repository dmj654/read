import SwiftUI

/// P1.5/P1.6/P1.9 小说阅读器：目录切换 + 章节正文分页 + 翻页 + 进度。
///
/// P5.2 无障碍与自适应：
/// - 正文尺寸随 Dynamic Type 缩放（`@ScaledMetric`），并限制超大字号下的行宽避免阅读困难。
/// - 翻页过渡遵循「减弱动态效果」（`ReaderMotionPolicy`），开启时改为无动画直接切换。
/// - 正文对 VoiceOver 可整体朗读，翻页按钮带明确标签与禁用态说明。
/// - iPad 常规宽度下限制正文最大宽度，避免超长行。
struct ReaderView: View {
    let source: SourceRule
    let bookURL: String
    @State private var vm: NovelReaderViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 18

    init(source: SourceRule, bookURL: String) {
        self.source = source
        self.bookURL = bookURL
        _vm = State(initialValue: NovelReaderViewModel(source: source))
    }

    private var currentText: String {
        vm.pages.indices.contains(vm.currentPage) ? vm.pages[vm.currentPage] : ""
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            chapterPicker

            if vm.isLoading {
                ProgressView("加载中…")
                    .accessibilityLabel("正在加载章节")
            }

            ScrollView {
                Text(currentText)
                    .font(.system(size: bodyFontSize))
                    .lineSpacing(bodyFontSize * 0.45)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.m)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                    .accessibilityLabel("正文内容")
                    .accessibilityValue(currentText)
                    .id(vm.currentPage)
                    .transition(ReaderMotionPolicy.transition(reduceMotion: reduceMotion))
            }
            .animation(ReaderMotionPolicy.animation(reduceMotion: reduceMotion), value: vm.currentPage)

            pagerBar
        }
        .navigationTitle(vm.currentChapterTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadTOC(bookURL: bookURL)
            if !vm.chapters.isEmpty { await vm.loadChapter(at: 0) }
        }
    }

    // MARK: 章节选择

    private var chapterPicker: some View {
        Picker("章节", selection: $vm.currentChapterIndex) {
            ForEach(Array(vm.chapters.enumerated()), id: \.element.id) { index, chapter in
                Text(chapter.title).tag(index)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, Spacing.m)
        .accessibilityLabel("选择章节")
        .onChange(of: vm.currentChapterIndex) { _, newValue in
            Task { await vm.loadChapter(at: newValue) }
        }
    }

    // MARK: 翻页栏

    private var pagerBar: some View {
        HStack(spacing: Spacing.m) {
            Button("上一页") { vm.prevPage() }
                .disabled(vm.currentPage == 0)
                .accessibilityLabel("上一页")
                .accessibilityHint(vm.currentPage == 0 ? "已是本章第一页" : "翻到前一页")

            Spacer()

            Text(A11yLabels.percent(vm.progress))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
                .monospacedDigit()
                .accessibilityLabel("本章进度 \(A11yLabels.percent(vm.progress))")

            Spacer()

            Button("下一页") { vm.nextPage() }
                .disabled(vm.currentPage >= vm.pages.count - 1)
                .accessibilityLabel("下一页")
                .accessibilityHint(vm.currentPage >= vm.pages.count - 1 ? "已是本章最后一页" : "翻到后一页")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
    }
}
