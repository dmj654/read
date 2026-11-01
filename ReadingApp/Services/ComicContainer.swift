import Foundation
import ZIPFoundation
import PDFKit
import UIKit

/// P3.2 本地漫画容器访问错误。
enum ComicContainerError: Error, Equatable {
    case unreadable(URL)
    case outOfRange(Int, Int)
    case unsupportedType(String)
    case renderFailed(Int)
}

/// P3.2 广告页判定（在线图片页与本地容器页通用）。
///
/// 规则语义：以 `/` 开头按正则匹配（命中即广告），否则按大小写不敏感子串包含判定。
enum ComicAdFilter {
    static func isAd(_ value: String, rule: String?) -> Bool {
        guard let rule, !rule.isEmpty else { return false }
        if rule.hasPrefix("/") {
            return !RuleEngine.evaluate(rule, source: value).isEmpty
        }
        return value.localizedCaseInsensitiveContains(rule)
    }
}

/// P3.2 本地漫画容器统一协议：CBZ 与 PDF 共用同一页访问接口。
protocol ComicPageProviding {
    var pageCount: Int { get }
    /// 取第 index 页的位图数据（PNG/JPEG 字节）。
    func pageData(at index: Int) throws -> Data
    /// 页标识（用于广告过滤，默认 `pageN`）；CBZ 返回归档内文件名。
    func pageName(at index: Int) -> String
}

extension ComicPageProviding {
    func pageName(at index: Int) -> String { "page\(index)" }
}

/// P3.2 CBZ（ZIP）容器：仅枚举图片条目并按自然序排列。
final class CBZArchive: ComicPageProviding {
    let url: URL
    private let archive: Archive
    /// 已筛选并排序的图片条目（自然序）。
    private let imageEntries: [Entry]

    init(url: URL) throws {
        self.url = url
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicContainerError.unreadable(url)
        }
        self.archive = archive
        self.imageEntries = archive
            .filter { Self.isImageEntry($0.path) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    var pageCount: Int { imageEntries.count }

    func pageData(at index: Int) throws -> Data {
        guard (0..<pageCount).contains(index) else {
            throw ComicContainerError.outOfRange(index, pageCount)
        }
        let entry = imageEntries[index]
        var data = Data()
        try archive.extract(entry) { data.append($0) }
        return data
    }

    func pageName(at index: Int) -> String {
        guard (0..<pageCount).contains(index) else { return "page\(index)" }
        return imageEntries[index].path
    }

    private static func isImageEntry(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".png") || lower.hasSuffix(".webp")
    }
}

/// P3.2 PDF 容器（PDFKit）：逐页渲染为位图（2x 保证清晰度）。
final class PDFDocumentWrapper: ComicPageProviding {
    let document: PDFDocument

    init(document: PDFDocument) { self.document = document }

    convenience init(url: URL) throws {
        guard let doc = PDFDocument(url: url) else {
            throw ComicContainerError.unreadable(url)
        }
        self.init(document: doc)
    }

    var pageCount: Int { document.pageCount }

    func pageData(at index: Int) throws -> Data {
        guard let page = document.page(at: index) else {
            throw ComicContainerError.outOfRange(index, pageCount)
        }
        let size = page.bounds(for: .mediaBox).size
        let scale: CGFloat = 2
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size.width * scale, height: size.height * scale)
        )
        let image = renderer.image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            UIColor.white.set()
            ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        guard let data = image.pngData() else {
            throw ComicContainerError.renderFailed(index)
        }
        return data
    }
}

/// P3.2 漫画容器统一枚举：屏蔽 CBZ / PDF 差异，供阅读器与视图模型消费。
enum ComicContainer: ComicPageProviding {
    case cbz(CBZArchive)
    case pdf(PDFDocumentWrapper)

    var pageCount: Int {
        switch self {
        case .cbz(let a): return a.pageCount
        case .pdf(let d): return d.pageCount
        }
    }

    func pageData(at index: Int) throws -> Data {
        switch self {
        case .cbz(let a): return try a.pageData(at: index)
        case .pdf(let d): return try d.pageData(at: index)
        }
    }

    func pageName(at index: Int) -> String {
        switch self {
        case .cbz(let a): return a.pageName(at: index)
        case .pdf(let d): return d.pageName(at: index)
        }
    }

    /// 依据文件扩展名自动选择容器类型构造。
    /// - Note: CBR/RAR 本期不支持（需转 CBZ）；遇到时抛 `unsupportedType`。
    static func open(url: URL) throws -> ComicContainer {
        switch url.pathExtension.lowercased() {
        case "cbz", "zip":
            return .cbz(try CBZArchive(url: url))
        case "pdf":
            return .pdf(try PDFDocumentWrapper(url: url))
        case "cbr", "rar":
            // P3 决策：CBR/RAR 后置到项目末期，先用 CBZ/ZIP/PDF + 通用图片。
            throw ComicContainerError.unsupportedType(url.pathExtension)
        default:
            throw ComicContainerError.unsupportedType(url.pathExtension)
        }
    }
}
