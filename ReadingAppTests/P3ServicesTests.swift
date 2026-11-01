import XCTest
import Foundation
import ZIPFoundation
import PDFKit
import UIKit
@testable import ReadingApp

// MARK: - P3 服务层（漫源解析 + 本地容器）单元测试

final class P3ServicesTests: XCTestCase {

    // MARK: P3.1 漫画书源解析（StubSession 零网络）

    func testFetchImagePagesExtractsAndFiltersAds() async throws {
        let html = """
        <div class="g"><img src="https://x.com/1.jpg"></div>
        <div class="g"><img src="https://x.com/ad.jpg"></div>
        <div class="g"><img src="https://x.com/2.jpg"></div>
        """
        let resp = HTTPURLResponse.fixture(status: 200, url: URL(string: "https://x.com/c1")!)
        let svc = ComicSourceService(network: NetworkService(session: StubSession(response: (Data(html.utf8), resp))))

        var source = SourceRule(name: "comic", type: .comic)
        source.imageListRule = "css>div.g"
        source.imageUrlRule = "css>img@src"
        source.adPageFilter = "/ad\\./"   // 命中 "ad.jpg" 的视为广告页剔除

        let pages = try await svc.fetchImagePages(chapterURL: "https://x.com/c1", source: source)
        XCTAssertEqual(pages.map { $0.imageURL }, ["https://x.com/1.jpg", "https://x.com/2.jpg"])
        XCTAssertFalse(pages.contains { $0.isAd })
    }

    func testFetchImagePagesPagination() async throws {
        // 第 1 页 1 张图 + 指向第 2 页的 next 链接；第 2 页 1 张图 + 无 next。
        let page1 = """
        <div class="g"><img src="https://x.com/a.jpg"></div>
        <a id="next" href="https://x.com/c2">下一页</a>
        """
        let page2 = """
        <div class="g"><img src="https://x.com/b.jpg"></div>
        """
        let router = MultiStubSession(routes: [
            "https://x.com/c1": page1,
            "https://x.com/c2": page2
        ])
        let svc = ComicSourceService(network: NetworkService(session: router))
        var source = SourceRule(name: "comic", type: .comic)
        source.imageListRule = "css>div.g"
        source.imageUrlRule = "css>img@src"
        source.nextPageRule = "css>a#next@href"

        let pages = try await svc.fetchImagePages(chapterURL: "https://x.com/c1", source: source)
        XCTAssertEqual(pages.map { $0.imageURL }, ["https://x.com/a.jpg", "https://x.com/b.jpg"])
    }

    func testFetchChapterListReusesTocRule() async throws {
        let html = """
        <ul><li><a href="/ch1">第1话</a></li><li><a href="/ch2">第2话</a></li></ul>
        """
        let resp = HTTPURLResponse.fixture(status: 200, url: URL(string: "https://x.com/book")!)
        let svc = ComicSourceService(network: NetworkService(session: StubSession(response: (Data(html.utf8), resp))))
        var source = SourceRule(name: "comic", type: .comic)
        source.ruleToc = #"{"chapterName":"css>li>a","chapterUrl":"css>li>a@href"}"#

        let chapters = try await svc.fetchChapterList(bookURL: "https://x.com/book", source: source)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第1话")
        XCTAssertEqual(chapters[0].url, "/ch1")
    }

    // MARK: P3.2 本地容器：CBZ

    func testCBZArchiveReadsSortedImages() throws {
        // 自然序验证：page2 应排在 page10 之前（区别于字典序），note.txt 非图片剔除。
        let url = makeCBZ(pages: ["page10.png", "page2.png", "page1.png", "note.txt"],
                          data: solidPNG(color: .blue))
        let container = try ComicContainer.open(url: url)
        guard case .cbz(let cbz) = container else { XCTFail("应为 CBZ"); return }
        XCTAssertEqual(cbz.pageCount, 3)   // note.txt 非图片被剔除
        XCTAssertEqual(cbz.pageName(at: 0), "page1.png")
        XCTAssertEqual(cbz.pageName(at: 1), "page2.png")
        XCTAssertEqual(cbz.pageName(at: 2), "page10.png")
        let data = try cbz.pageData(at: 0)
        XCTAssertGreaterThan(data.count, 0)
    }

    func testCBZOpenUnsupportedTypeThrows() {
        let url = URL(fileURLWithPath: "/tmp/foo.cbr")
        XCTAssertThrowsError(try ComicContainer.open(url: url)) { err in
            XCTAssertEqual(err as? ComicContainerError, .unsupportedType("cbr"))
        }
    }

    // MARK: P3.2 本地容器：PDF

    func testPDFContainerPageCountAndRender() throws {
        let url = makePDF(pageCount: 3)
        let container = try ComicContainer.open(url: url)
        guard case .pdf(let pdf) = container else { XCTFail("应为 PDF"); return }
        XCTAssertEqual(pdf.pageCount, 3)
        let data = try pdf.pageData(at: 1)
        XCTAssertGreaterThan(data.count, 0)   // 渲染为 PNG 字节
    }

    // MARK: P3.2 广告页判定

    func testComicAdFilterRegexAndSubstring() {
        XCTAssertTrue(ComicAdFilter.isAd("https://x.com/ad.jpg", rule: "/ad\\./"))
        XCTAssertFalse(ComicAdFilter.isAd("https://x.com/1.jpg", rule: "/ad\\./"))
        XCTAssertTrue(ComicAdFilter.isAd("page_ad.png", rule: "ad"))
        XCTAssertFalse(ComicAdFilter.isAd("page1.png", rule: "ad"))
        XCTAssertFalse(ComicAdFilter.isAd("anything", rule: nil))
    }

    // MARK: 测试夹具构建

    /// 在临时目录写一个合法 CBZ（ZIP），返回其 URL。
    private func makeCBZ(pages: [String], data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("cbz")
        guard var archive = Archive(url: url, accessMode: .create) else {
            XCTFail("无法创建 CBZ"); return url
        }
        for name in pages {
            _ = try? archive.addEntry(with: name, type: .file,
                                     uncompressedSize: UInt32(data.count)) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return url
    }

    /// 在临时目录写一个合法 PDF（N 页纯色图），返回其 URL。
    private func makePDF(pageCount: Int) -> URL {
        let doc = PDFDocument()
        for _ in 0..<pageCount {
            let img = solidUIImage(color: .green)
            if let page = PDFPage(image: img) { doc.insert(page, at: doc.pageCount) }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        XCTAssertTrue(doc.write(to: url))
        return url
    }

    private func solidPNG(color: UIColor) -> Data {
        solidUIImage(color: color).pngData()!
    }

    private func solidUIImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }
}

// MARK: - 多路由 Stub Session（按 URL 返回不同响应，用于分页测试）

final class MultiStubSession: URLSessionProtocol, @unchecked Sendable {
    let routes: [String: String]   // url -> html 文本
    init(routes: [String: String]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url?.absoluteString ?? ""
        let html = routes[url] ?? ""
        let resp = HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!,
                                   statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(html.utf8), resp)
    }
}
