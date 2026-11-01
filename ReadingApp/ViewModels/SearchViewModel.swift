import Foundation
import Observation

/// P1.2/P1.8 搜索 ViewModel：关键词 → 跨源结果，含加载/错误状态。
@Observable
final class SearchViewModel {
    private let service: SearchService
    private let repository: SourceRepository
    var keyword: String = ""
    var results: [SearchResult] = []
    var isLoading = false
    var error: String?

    init(service: SearchService = SearchService(), repository: SourceRepository) {
        self.service = service
        self.repository = repository
    }

    @MainActor
    func search() async {
        guard !keyword.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let sources = try repository.enabledSources()
            results = try await service.search(keyword: keyword, sources: sources)
        } catch {
            self.error = "搜索失败：\(error.localizedDescription)"
            results = []
        }
    }
}
