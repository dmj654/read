import XCTest
import Foundation
import SwiftData
@testable import ReadingApp

// MARK: - P4.2/P4.3/P4.4 同步模型 / 凭据 / 服务 单元测试

@MainActor
final class P4SyncTests: XCTestCase {

    // MARK: P4.2 编解码往返

    func testSnapshotCodableRoundTrip() throws {
        let book = BookDTO(sourceID: "s1", title: "T", author: "A", type: "novel",
                           progress: 0.5, updatedAt: Date(timeIntervalSince1970: 1000),
                           coverURL: nil, format: nil, pageCount: nil, bookURL: nil)
        let snapshot = SyncSnapshot(version: 3, updatedAt: Date(timeIntervalSince1970: 1000),
                                    deviceID: "d", books: [book], sources: [], settings: nil)
        let data = try SyncSnapshot.makeEncoder().encode(snapshot)
        let back = try SyncSnapshot.makeDecoder().decode(SyncSnapshot.self, from: data)
        XCTAssertEqual(snapshot, back)
    }

    // MARK: P4.2 冲突合并（最后写入胜出）

    func testMergeBooksLastWriteWins() {
        let older = BookDTO(sourceID: "s", title: "T", author: "", type: "novel", progress: 0.2,
                            updatedAt: Date(timeIntervalSince1970: 100),
                            coverURL: nil, format: nil, pageCount: nil, bookURL: nil)
        let newer = BookDTO(sourceID: "s", title: "T", author: "", type: "novel", progress: 0.8,
                            updatedAt: Date(timeIntervalSince1970: 200),
                            coverURL: nil, format: nil, pageCount: nil, bookURL: nil)
        let merged = SyncMerge.mergeBooks([older], [newer])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].progress, 0.8)
    }

    func testMergeVersionIncrements() {
        let local = SyncSnapshot(version: 0, updatedAt: Date(timeIntervalSince1970: 100),
                                 deviceID: "a", books: [], sources: [], settings: nil)
        let remote = SyncSnapshot(version: 7, updatedAt: Date(timeIntervalSince1970: 200),
                                  deviceID: "b", books: [], sources: [], settings: nil)
        let merged = SyncMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.version, 8)
    }

    // MARK: P4.3 凭据存储

    func testInMemoryCredentialStore() throws {
        let store = InMemoryCredentialStore()
        try store.setPassword("p", for: "u")
        XCTAssertEqual(store.password(for: "u"), "p")
        store.deletePassword(for: "u")
        XCTAssertNil(store.password(for: "u"))
    }

    // MARK: P4.4 同步服务：首次推送

    func testFirstSyncUploadsAndBacksUp() async throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let config = try SyncConfig.loadOrCreate(in: ctx)
        config.serverURL = "https://nas.example.com/webdav"
        config.username = "u"
        let creds = InMemoryCredentialStore()
        try creds.setPassword("p", for: "u")

        ctx.insert(Book(title: "B1", type: .novel, sourceID: "s1", progress: 0.3))
        try ctx.save()

        let stub = StubWebDAV()
        let backupDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = SyncService(context: ctx, config: config, credentials: creds,
                                  backupDirectory: backupDir,
                                  makeClient: { _, _ in stub })

        let result = try await service.syncNow()
        XCTAssertTrue(result.remoteWasEmpty)
        XCTAssertEqual(result.version, 1)
        XCTAssertNotNil(stub.stored)
        XCTAssertEqual(config.lastSyncVersion, 1)

        let backups = (try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(backups.count, 1)
    }

    // MARK: P4.4 同步服务：远端较新进度合并（LWW）

    func testSecondSyncMergesNewerRemoteProgress() async throws {
        let ctx = ModelContext(try PersistenceController.inMemory())
        let config = try SyncConfig.loadOrCreate(in: ctx)
        config.serverURL = "https://nas.example.com/webdav"
        config.username = "u"
        let creds = InMemoryCredentialStore()

        // 本地：进度 0.2
        let local = Book(title: "B1", type: .novel, sourceID: "s1", progress: 0.2)
        local.updatedAt = .now
        ctx.insert(local)
        try ctx.save()

        // 远端：同书进度 0.9，更新时间更晚 → 应胜出
        let remoteBook = BookDTO(sourceID: "s1", title: "B1", author: "", type: "novel", progress: 0.9,
                                 updatedAt: Date().addingTimeInterval(3600),
                                 coverURL: nil, format: nil, pageCount: nil, bookURL: nil)
        let remote = SyncSnapshot(version: 5, updatedAt: Date().addingTimeInterval(3600),
                                  deviceID: "remote", books: [remoteBook], sources: [], settings: nil)
        let stub = StubWebDAV()
        stub.stored = try SyncSnapshot.makeEncoder().encode(remote)

        let service = SyncService(context: ctx, config: config, credentials: creds,
                                  makeClient: { _, _ in stub })
        let result = try await service.syncNow()

        XCTAssertFalse(result.remoteWasEmpty)
        XCTAssertEqual(result.version, 6)   // max(0,5)+1

        let books = try ctx.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.first?.progress ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertEqual(books.count, 1)      // 按 syncKey 去重，不重复插入
    }
}

// MARK: - WebDAV 服务桩

final class StubWebDAV: WebDAVServicing {
    var stored: Data?
    private(set) var uploaded: [Data] = []
    var testError: Error?

    func download(path: String) async throws -> Data? { stored }

    func upload(path: String, data: Data) async throws {
        uploaded.append(data)
        stored = data
    }

    func testConnection() async throws {
        if let testError { throw testError }
    }
}
