import XCTest
import Foundation
import SwiftData
@testable import ReadingApp

// MARK: - P3 漫画图片页缓存/下载 单元测试

@MainActor
final class P3CacheTests: XCTestCase {

    func testCacheFileNameAndEnqueueTriggersDownload() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileStore = DownloadFileManager(baseDirectory: tmp)
        let runner = StubDownloadRunner()
        let manager = DownloadManager(
            store: DownloadStore(context: ModelContext(try PersistenceController.inMemory())),
            runner: runner, maxConcurrent: 1
        )
        let cache = ComicPageCacheService(manager: manager, fileStore: fileStore)

        let name = cache.enqueuePage(bookID: "book1", chapter: "ch1", index: 0, url: "https://x.com/p0.jpg")
        XCTAssertEqual(name, "book1/ch1/0.img")
        XCTAssertEqual(runner.started.count, 1)
        XCTAssertEqual(runner.started.first?.url, "https://x.com/p0.jpg")

        // 尚未真正下载（桩无落盘），本地 URL 应为 nil。
        XCTAssertNil(cache.localURL(for: name))
    }

    func testCacheLocalURLResolvesWhenFileExists() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileStore = DownloadFileManager(baseDirectory: tmp)
        let cache = ComicPageCacheService(
            manager: DownloadManager(
                store: DownloadStore(context: ModelContext(try PersistenceController.inMemory())),
                runner: StubDownloadRunner(), maxConcurrent: 1
            ),
            fileStore: fileStore
        )
        let name = "book1/ch1/3.img"
        // 模拟已落盘：直接在落盘目录写入对应文件。
        let dest = fileStore.destinationURL(for: name)
        try "downloaded".write(to: dest, atomically: true, encoding: .utf8)
        XCTAssertTrue(fileStore.exists(fileName: name))
        XCTAssertEqual(cache.localURL(for: name), dest)
    }
}
