import XCTest
import Foundation
@testable import ReadingApp

// MARK: - P4.1 WebDAV 客户端单元测试（零网络）

final class P4WebDAVTests: XCTestCase {

    private func makeClient(_ stub: RecordingStubSession) -> WebDAVClient {
        WebDAVClient(
            config: WebDAVConfig(baseURL: "https://nas.example.com/webdav",
                                 username: "u", directory: "ReadingApp"),
            password: "p",
            network: NetworkService(session: stub, maxRetry: 0)
        )
    }

    func testListParsesMultistatus() async throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/webdav/ReadingApp/</D:href>
            <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
          </D:response>
          <D:response>
            <D:href>/webdav/ReadingApp/sync.json</D:href>
            <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>42</D:getcontentlength></D:prop></D:propstat>
          </D:response>
        </D:multistatus>
        """
        let stub = RecordingStubSession { _ in (207, [:], Data(xml.utf8)) }
        let items = try await makeClient(stub).list()

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertEqual(items[1].contentLength, 42)

        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.httpMethod, "PROPFIND")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Depth"), "1")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    }

    func testPutSendsBody() async throws {
        let stub = RecordingStubSession { _ in (201, [:], Data()) }
        try await makeClient(stub).put("sync.json", data: Data("hello".utf8))

        let request = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.httpBody, Data("hello".utf8))
    }

    func testDownloadReturnsNilOn404() async throws {
        let stub = RecordingStubSession { _ in (404, [:], Data()) }
        let data = try await makeClient(stub).download(path: "missing.json")
        XCTAssertNil(data)
    }

    func testTestConnectionCreatesMissingCollection() async throws {
        let stub = RecordingStubSession { request in
            if request.httpMethod == "PROPFIND" { return (404, [:], Data()) }
            return (201, [:], Data())
        }
        try await makeClient(stub).testConnection()
        XCTAssertEqual(stub.requests.map { $0.httpMethod }, ["PROPFIND", "MKCOL"])
    }

    func testUnauthorizedMapsToError() async throws {
        let stub = RecordingStubSession { _ in (401, [:], Data()) }
        do {
            _ = try await makeClient(stub).get("sync.json")
            XCTFail("应抛鉴权错误")
        } catch WebDAVError.unauthorized {
            // 预期
        }
    }
}

// MARK: - 记录型桩 Session（按请求返回响应 + 记录请求）

final class RecordingStubSession: URLSessionProtocol, @unchecked Sendable {
    private let handler: (URLRequest) -> (Int, [String: String], Data)
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    init(handler: @escaping (URLRequest) -> (Int, [String: String], Data)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); _requests.append(request); lock.unlock()
        let (status, headers, body) = handler(request)
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}
