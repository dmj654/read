import XCTest
import Foundation
import ZIPFoundation
import SwiftData
import UIKit
@testable import ReadingApp

// MARK: - P3 漫画阅读器 ViewModel 单元测试

@MainActor
final class P3ViewModelsTests: XCTestCase {

    // MARK: P3.4 本地容器：翻页 / 进度

    func testLocalContainerNavigationAndProgress() async throws {
        let url = makeCBZ(pages: ["page1.png", "page2.png", "page3.png"], color: .blue)
        let container = try ComicContainer.open(url: url)
        let book = Book(title: "测试漫画", type: .comic, progress: 0)
        let vm = ComicReaderViewModel(loadSource: .local(container, adFilter: nil), book: book)
        await vm.load()
        XCTAssertEqual(vm.pageCount, 3)
        XCTAssertEqual(vm.currentIndex, 0)

        vm.next()
        XCTAssertEqual(vm.currentIndex, 1)
        vm.next()
        XCTAssertEqual(vm.currentIndex, 2)
        XCTAssertFalse(vm.canGoNext)
        vm.next()   // 越界保护
        XCTAssertEqual(vm.currentIndex, 2)
        vm.prev()
        XCTAssertEqual(vm.currentIndex, 1)

        // 进度持久化到 Book
        XCTAssertEqual(book.pageCount, 3)
        XCTAssertEqual(book.progress, 1.0 / 2.0, accuracy: 1e-9)
    }

    func testLocalContainerAdFilter() async throws {
        // 文件名含 "ad" 的页，经 adFilter="ad" 过滤后剔除。
        let url = makeCBZ(pages: ["page1.png", "ad_sponsor.png", "page2.png"], color: .red)
        let container = try ComicContainer.open(url: url)
        let vm = ComicReaderViewModel(loadSource: .local(container, adFilter: "ad"))
        await vm.load()
        XCTAssertEqual(vm.pageCount, 2)   // ad_sponsor 被剔除
        XCTAssertEqual(vm.pages.map { $0.imageURL }, ["page1.png", "page2.png"])
    }

    // MARK: P3.4 在线：图片页解析 + 广告过滤 + 缓存触发

    func testOnlineLoadFiltersAdsAndEnqueuesCache() async throws {
        let html = """
        <div class="g"><img src="https://x.com/1.jpg"></div>
        <div class="g"><img src="https://x.com/ad.jpg"></div>
        <div class="g"><img src="https://x.com/2.jpg"></div>
        """
        let resp = HTTPURLResponse.fixture(status: 200, url: URL(string: "https://x.com/c1")!)
        let service = ComicSourceService(network: NetworkService(session: StubSession(response: (Data(html.utf8), resp))))
        var source = SourceRule(name: "comic", type: .comic)
        source.imageListRule = "css>div.g"
        source.imageUrlRule = "css>img@src"
        source.adPageFilter = "/ad\\./"

        let downloader = StubPageDownloader()
        let vm = ComicReaderViewModel(
            loadSource: .online(source: source, chapterURL: "https://x.com/c1",
                                downloader: downloader, service: service),
            book: Book(title: "online", type: .comic)
        )
        await vm.load()
        XCTAssertEqual(vm.pageCount, 2)
        XCTAssertEqual(downloader.enqueued.count, 2)   // 两页有效图被缓存入队
        XCTAssertTrue(downloader.enqueued.contains { $0.url == "https://x.com/1.jpg" })

        // 在线页解析：本地无缓存时回退远程 URL
        let page = vm.pages[0]
        let resolved = vm.resolvedURL(for: page, downloader: downloader)
        XCTAssertEqual(resolved?.absoluteString, "https://x.com/1.jpg")
    }

    // MARK: 测试夹具

    private func makeCBZ(pages: [String], color: UIColor) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("cbz")
        guard var archive = Archive(url: url, accessMode: .create) else {
            XCTFail("无法创建 CBZ"); return url
        }
        let data = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
            .image { ctx in color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
            .pngData()!
        for name in pages {
            _ = try? archive.addEntry(with: name, type: .file,
                                     uncompressedSize: UInt32(data.count)) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return url
    }
}

/// P3 测试桩：记录入队的图片页，localURL 恒返回 nil（回退远程）。
@MainActor
final class StubPageDownloader: PageDownloading {
    struct Entry { let bookID: String; let chapter: String; let index: Int; let url: String }
    private(set) var enqueued: [Entry] = []

    func enqueuePage(bookID: String, chapter: String, index: Int, url: String) -> String {
        enqueued.append(Entry(bookID: bookID, chapter: chapter, index: index, url: url))
        return "\(bookID)/\(chapter)/\(index).img"
    }

    func localURL(for fileName: String) -> URL? { nil }
}
