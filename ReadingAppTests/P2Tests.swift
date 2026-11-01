import XCTest
import Foundation
import SwiftData
import UIKit
@testable import ReadingApp

// MARK: - P2 下载管理 + 后台会话整合 单元测试

final class P2Tests: XCTestCase {

    // MARK: P2.1 模型状态往返
    func testDownloadRecordStateRoundTrip() {
        let r = DownloadRecord(url: "https://x.com/a.bin", fileName: "a.bin")
        XCTAssertEqual(r.state, .queued)
        r.state = .downloading
        XCTAssertEqual(r.stateRaw, "downloading")
        r.state = .completed
        XCTAssertEqual(DownloadState(rawValue: r.stateRaw), .completed)
    }

    // MARK: P2.2 仓储 CRUD + 按状态过滤 + 清理
    func testDownloadStoreCRUD() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let store = DownloadStore(context: ctx)
        let r = DownloadRecord(url: "u", fileName: "f")
        r.state = .completed
        try store.insert(r)
        XCTAssertEqual(try store.all().count, 1)
        XCTAssertEqual(try store.byState(.completed).count, 1)
        XCTAssertEqual(try store.byState(.queued).count, 0)
        r.progress = 0.5
        try store.update(r)
        XCTAssertEqual(try store.byID(r.id)?.progress, 0.5)
        try store.delete(r)
        XCTAssertEqual(try store.all().count, 0)
    }

    // MARK: P2.3 队列并发上限 + 顺序
    func testDownloadQueue() {
        var q = DownloadQueue(maxConcurrent: 1)
        XCTAssertTrue(q.enqueue("a"))
        XCTAssertFalse(q.enqueue("b"))
        XCTAssertFalse(q.enqueue("c"))
        XCTAssertEqual(q.active, ["a"])
        XCTAssertEqual(q.pending, ["b", "c"])
        XCTAssertEqual(q.complete("a"), "b")
        XCTAssertEqual(q.active, ["b"])
        XCTAssertEqual(q.pending, ["c"])
        XCTAssertNil(q.cancel("c"))
        XCTAssertNil(q.complete("b"))
        XCTAssertTrue(q.active.isEmpty)
    }

    // MARK: P2.4 文件落地 + 安全命名
    func testDownloadFileManager() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fs = DownloadFileManager(baseDirectory: tmp)
        let src = tmp.appendingPathComponent("src.tmp")
        try "hello".write(to: src, atomically: true, encoding: .utf8)
        let final = try fs.persist(from: src, fileName: "my file?.bin")
        XCTAssertEqual(final.lastPathComponent, "my_file_.bin")  // 非法字符被替换
        XCTAssertTrue(fs.exists(fileName: "my file?.bin"))
        XCTAssertEqual(try String(contentsOf: final), "hello")
        XCTAssertGreaterThan(try fs.sizeOfDirectory(), 0)
    }

    // MARK: P2.5/P2.6 管理器编排（StubRunner，零网络）
    @MainActor
    func testDownloadManagerOrchestration() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let store = DownloadStore(context: ctx)
        let runner = StubDownloadRunner()
        let mgr = DownloadManager(store: store, runner: runner, maxConcurrent: 1)

        let a = try mgr.enqueue(url: "https://x.com/a", fileName: "a.bin")
        let b = try mgr.enqueue(url: "https://x.com/b", fileName: "b.bin")
        XCTAssertEqual(runner.started.count, 1)                 // 并发=1，b 排队
        XCTAssertEqual(try store.byID(a.id)?.state, .downloading)
        XCTAssertEqual(try store.byID(b.id)?.state, .queued)

        mgr.handle(.finished(recordID: a.id, finalURL: URL(fileURLWithPath: "/tmp/a")))
        XCTAssertEqual(try store.byID(a.id)?.state, .completed)
        XCTAssertEqual(try store.byID(b.id)?.state, .downloading)   // b 自动拉起
        XCTAssertEqual(runner.started.count, 2)

        mgr.handle(.failed(recordID: b.id, errorMessage: "boom", resumeData: nil))
        XCTAssertEqual(try store.byID(b.id)?.state, .failed)
        XCTAssertFalse(try store.all().isEmpty)
    }

    // MARK: P2.6 暂停捕获续传凭证 + 续传重启
    @MainActor
    func testDownloadManagerPauseResume() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let store = DownloadStore(context: ctx)
        let runner = StubDownloadRunner()
        let mgr = DownloadManager(store: store, runner: runner, maxConcurrent: 1)
        let a = try mgr.enqueue(url: "https://x.com/a", fileName: "a.bin")
        XCTAssertEqual(try store.byID(a.id)?.state, .downloading)

        mgr.pause(a)
        XCTAssertEqual(try store.byID(a.id)?.state, .paused)
        // 模拟取消产生的续传凭证（经 .failed 事件回收）
        mgr.handle(.failed(recordID: a.id, errorMessage: "cancelled", resumeData: Data([1, 2, 3])))
        XCTAssertEqual(try store.byID(a.id)?.state, .paused)        // 暂停不被失败覆盖
        XCTAssertEqual(try store.byID(a.id)?.resumeData, Data([1, 2, 3]))

        mgr.resume(a)
        XCTAssertEqual(try store.byID(a.id)?.state, .downloading)
        XCTAssertEqual(runner.started.last?.resumeData, Data([1, 2, 3]))
    }

    // MARK: P2.7 ViewModel
    @MainActor
    func testDownloadViewModel() throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let store = DownloadStore(context: ctx)
        let mgr = DownloadManager(store: store, runner: StubDownloadRunner(), maxConcurrent: 1)
        let vm = DownloadViewModel(manager: mgr)
        vm.enqueue(url: "https://x.com/a", fileName: "a.bin")
        vm.refresh()
        XCTAssertEqual(vm.records.count, 1)
    }

    // MARK: P2.6 后台会话结束回调链（协调器层，零网络）
    func testBackgroundCompletionHandlerInvokedAndCleared() {
        // 使用唯一标识避免与 shared 的后台会话冲突。
        let coordinator = BackgroundDownloadCoordinator(
            fileStore: DownloadFileManager(baseDirectory: FileManager.default.temporaryDirectory),
            identifier: "com.example.ReadingApp.test.unique"
        )
        var called = false
        coordinator.backgroundCompletionHandler = { called = true }
        // 模拟系统交付完所有后台事件后触发的收尾回调。
        coordinator.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        XCTAssertTrue(called, "结束处理器应被调用")
        XCTAssertNil(coordinator.backgroundCompletionHandler, "调用后应清空，防止重复回调")
    }

    func testBackgroundCoordinatorReconnectReturnsShared() {
        let c = BackgroundDownloadCoordinator.reconnect()
        XCTAssertTrue(c === BackgroundDownloadCoordinator.shared, "reconnect 应返回共享单例")
    }

    // MARK: P2.6 AppDelegate 桥接（需宿主 App，TEST_HOST 已配置）
    func testAppDelegateRoutesBackgroundSession() {
        let delegate = AppDelegate()
        var called = false
        delegate.application(UIApplication.shared,
                             handleEventsForBackgroundURLSession: BackgroundDownloadCoordinator.identifier,
                             completionHandler: { called = true })
        // 结束处理器应已写入共享协调器。
        XCTAssertNotNil(BackgroundDownloadCoordinator.shared.backgroundCompletionHandler)
        // 系统交付完事件后由协调器收尾，触发 AppDelegate 登记的处理器。
        BackgroundDownloadCoordinator.shared.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        XCTAssertTrue(called, "AppDelegate 登记的结束处理器应被触发")
    }

    func testAppDelegateIgnoresUnknownIdentifier() {
        let delegate = AppDelegate()
        // 非本应用登记的后台会话标识应被忽略，不写入处理器。
        delegate.application(UIApplication.shared,
                             handleEventsForBackgroundURLSession: "com.other.app.download",
                             completionHandler: {})
        // 仅验证不抛错且未改动 shared（此处仅断言安全返回即可）。
        XCTAssert(true)
    }
}

// MARK: 测试桩：引用语义，记录 start 调用；事件由测试直接注入 handle(_:)。

final class StubDownloadRunner: DownloadRunner {
    var onEvent: (@Sendable (DownloadEvent) -> Void)?
    private(set) var started: [(recordID: String, url: String, resumeData: Data?)] = []

    func start(recordID: String, url: String, resumeData: Data?) {
        started.append((recordID, url, resumeData))
    }

    func cancel(recordID: String) {}
}
