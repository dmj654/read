import Foundation
import Observation

/// P1.5/P1.6/P1.8 小说阅读器 ViewModel：目录加载、章节正文分页、翻页与进度。
@Observable
final class NovelReaderViewModel {
    private let contentService: NovelContentService
    let source: SourceRule
    var chapters: [Chapter] = []
    var currentChapterIndex = 0
    var pages: [String] = []
    var currentPage = 0
    var isLoading = false

    init(contentService: NovelContentService = NovelContentService(), source: SourceRule) {
        self.contentService = contentService
        self.source = source
    }

    @MainActor
    func loadTOC(bookURL: String) async {
        isLoading = true
        defer { isLoading = false }
        chapters = (try? await contentService.fetchTOC(bookURL: bookURL, source: source)) ?? []
    }

    @MainActor
    func loadChapter(at index: Int, charsPerPage: Int = 800) async {
        guard chapters.indices.contains(index) else { return }
        currentChapterIndex = index
        isLoading = true
        defer { isLoading = false }
        let text = (try? await contentService.fetchContent(chapterURL: chapters[index].url, source: source)) ?? ""
        pages = ReaderPagination.paginate(text, charsPerPage: charsPerPage)
        currentPage = 0
    }

    func nextPage() { if currentPage < pages.count - 1 { currentPage += 1 } }
    func prevPage() { if currentPage > 0 { currentPage -= 1 } }

    var progress: Double { pages.isEmpty ? 0 : Double(currentPage) / Double(pages.count) }
    var currentChapterTitle: String { chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : "" }
}
