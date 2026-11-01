import XCTest
import SwiftData
import Foundation
@testable import ReadingApp

// MARK: - 桩 URLSession 实现（无网络，可控）

final class StubSession: URLSessionProtocol, @unchecked Sendable {
    let response: (Data, HTTPURLResponse)
    private let lock = NSLock()
    private var _active = 0
    var maxActive = 0

    init(response: (Data, HTTPURLResponse)) { self.response = response }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); _active += 1; maxActive = max(maxActive, _active); lock.unlock()
        defer { lock.lock(); _active -= 1; lock.unlock() }
        try? await Task.sleep(nanoseconds: 20_000_000)   // 让并发重叠可观测
        return response
    }
}

final class FlakySession: URLSessionProtocol, @unchecked Sendable {
    var failRemaining: Int
    let error: Error
    var calls = 0
    init(failRemaining: Int, error: Error = URLError(.timedOut)) {
        self.failRemaining = failRemaining; self.error = error
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        if failRemaining > 0 { failRemaining -= 1; throw error }
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("ok".utf8), resp)
    }
}

final class StatusFlakySession: URLSessionProtocol, @unchecked Sendable {
    var calls = 0
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        let code = calls == 1 ? 503 : 200
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (Data(), resp)
    }
}

final class NotFoundSession: URLSessionProtocol, @unchecked Sendable {
    var calls = 0
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        let resp = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        return (Data(), resp)
    }
}

extension HTTPURLResponse {
    static func fixture(status: Int = 200,
                       url: URL = URL(string: "https://example.com")!,
                       headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

// MARK: - P0.6 PersistenceController

final class PersistenceControllerTests: XCTestCase {

    func testInMemoryIsolation() throws {
        let c1 = try PersistenceController.inMemory()
        let c2 = try PersistenceController.inMemory()
        let ctx1 = ModelContext(c1)
        ctx1.insert(Book(title: "A"))
        try ctx1.save()
        let inC2 = try ModelContext(c2).fetch(FetchDescriptor<Book>())
        XCTAssertEqual(inC2.count, 0)
    }

    func testSchemaIncludesAllModels() throws {
        let c = try PersistenceController.inMemory()
        let ctx = ModelContext(c)
        ctx.insert(SourceRule(name: "s"))
        ctx.insert(AppSettings())
        ctx.insert(Book(title: "b"))
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SourceRule>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AppSettings>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Book>()).count, 1)
    }

    func testFreshContainerEmpty() throws {
        let c = try PersistenceController.inMemory()
        let ctx = ModelContext(c)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Book>()).count, 0)
    }
}

// MARK: - P0.7–P0.11 NetworkService

final class NetworkServiceTests: XCTestCase {

    private var baseURL: URL { URL(string: "https://example.com")! }

    // P0.7：异步 GET 返回数据与响应
    func testFetchSuccess() async throws {
        let resp = HTTPURLResponse.fixture(status: 200, url: baseURL)
        let svc = NetworkService(session: StubSession(response: (Data("hello".utf8), resp)))
        let (data, http) = try await svc.data(for: Request(url: baseURL))
        XCTAssertEqual(data, Data("hello".utf8))
        XCTAssertEqual(http.statusCode, 200)
    }

    // P0.7：非 2xx 抛 badStatus
    func testNon2xxThrows() async {
        let resp = HTTPURLResponse.fixture(status: 404, url: baseURL)
        let svc = NetworkService(session: StubSession(response: (Data(), resp)))
        do {
            _ = try await svc.data(for: Request(url: baseURL))
            XCTFail("应抛出 badStatus(404)")
        } catch NetworkError.badStatus(let code) {
            XCTAssertEqual(code, 404)
        } catch { XCTFail("错误类型不符: \(error)") }
    }

    // P0.8：Cookie 响应吸收 + 下次请求注入（通过 jar 校验）
    func testCookieRoundTrip() async throws {
        var headers: [String: String] = [:]
        headers["Set-Cookie"] = "sid=1; Path=/"
        let resp = HTTPURLResponse.fixture(status: 200, url: baseURL, headers: headers)
        let jar = CookieJar()
        let svc = NetworkService(session: StubSession(response: (Data(), resp)), cookieJar: jar)
        _ = try await svc.data(for: Request(url: baseURL))
        XCTAssertEqual(jar.cookies(for: baseURL).first?.value, "1")
    }

    // P0.9：重试后成功（2 失败 + 1 成功 = 3 次调用）
    func testRetryThenSucceeds() async throws {
        let flaky = FlakySession(failRemaining: 2)
        let svc = NetworkService(session: flaky, maxRetry: 3)
        let (data, _) = try await svc.data(for: Request(url: baseURL))
        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual(flaky.calls, 3)
    }

    // P0.9：5xx 触发重试，4xx 不重试
    func test5xxRetries4xxDoesNot() async {
        let s5 = StatusFlakySession()
        let svc5 = NetworkService(session: s5, maxRetry: 3)
        _ = try? await svc5.data(for: Request(url: baseURL))
        XCTAssertEqual(s5.calls, 2)   // 503 → 重试 → 200

        let s4 = NotFoundSession()
        let svc4 = NetworkService(session: s4, maxRetry: 3)
        do { _ = try await svc4.data(for: Request(url: baseURL)); XCTFail() }
        catch NetworkError.badStatus(let code) { XCTAssertEqual(code, 404) }
        catch { XCTFail() }
        XCTAssertEqual(s4.calls, 1)   // 不重试
    }

    // P0.10：并发上限（20 并发，上限 4，实际峰值 ≤ 4）
    func testConcurrencyLimit() async throws {
        let stub = StubSession(response: (Data(), HTTPURLResponse.fixture(status: 200, url: baseURL)))
        let svc = NetworkService(session: stub, maxConcurrency: 4)
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try await svc.data(for: Request(url: self.baseURL))
                }
            }
        }
        XCTAssertLessThanOrEqual(stub.maxActive, 4)
    }

    // P0.11：本地日志随开关（关闭无记录，开启有记录；绝不外发）
    func testLoggingToggle() async throws {
        let logger = NetworkLogger.shared
        logger.clear(); logger.setEnabled(false)
        _ = try? await NetworkService(
            session: StubSession(response: (Data(), HTTPURLResponse.fixture(status: 200, url: baseURL))),
            logger: logger
        ).data(for: Request(url: baseURL))
        let before = logger.entries().count

        logger.setEnabled(true)
        _ = try? await NetworkService(
            session: StubSession(response: (Data(), HTTPURLResponse.fixture(status: 200, url: baseURL))),
            logger: logger
        ).data(for: Request(url: baseURL))
        let after = logger.entries().count

        XCTAssertGreaterThan(after, before)
        logger.setEnabled(false)
    }
}

// MARK: - P0.12 后台会话

final class BackgroundSessionTests: XCTestCase {
    func testBackgroundConfig() {
        let session = NetworkSessionFactory.background(forIdentifier: "com.example.bg")
        XCTAssertTrue(session.configuration.isBackground)
        XCTAssertEqual(session.configuration.identifier, "com.example.bg")
    }
}
