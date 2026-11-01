import Foundation

/// P1.6 阅读器分页：纯函数，按段落填充每页至字符上限。
/// 真实分页在 P3 升级为 CoreText 测量；此处保证逻辑可测、零依赖。
enum ReaderPagination {
    /// 将正文按段落切分，顺序填充进每页（charsPerPage 为每页字符软上限）。
    static func paginate(_ text: String, charsPerPage: Int) -> [String] {
        guard charsPerPage > 0 else { return [text] }
        let paragraphs = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return [text] }

        var pages: [String] = []
        var current = ""
        for p in paragraphs {
            if !current.isEmpty, current.count + p.count + 1 > charsPerPage {
                pages.append(current)
                current = p
            } else {
                current = current.isEmpty ? p : current + "\n" + p
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}
