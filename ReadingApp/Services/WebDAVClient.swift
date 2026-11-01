import Foundation

/// P4.1 WebDAV 连接配置（密码单独存 Keychain，不在此结构内，避免落库）。
struct WebDAVConfig: Equatable, Sendable {
    var baseURL: String        // 例如 https://nas.example.com/webdav
    var username: String
    var directory: String      // 远端子目录，例如 ReadingApp（可为空）

    init(baseURL: String = "", username: String = "", directory: String = "ReadingApp") {
        self.baseURL = baseURL
        self.username = username
        self.directory = directory
    }
}

/// P4.1 WebDAV 资源项（PROPFIND 结果）。
struct WebDAVItem: Equatable, Sendable {
    let href: String
    let isDirectory: Bool
    let contentLength: Int?
    let lastModified: Date?
}

/// P4.1 WebDAV 错误（统一归一化 `NetworkError`）。
enum WebDAVError: Error, Equatable {
    case invalidURL
    case notFound
    case unauthorized
    case badStatus(Int)
    case parse

    static func map(_ error: Error) -> WebDAVError {
        if let e = error as? WebDAVError { return e }
        if case NetworkError.badStatus(let code) = error {
            switch code {
            case 401, 403: return .unauthorized
            case 404: return .notFound
            default: return .badStatus(code)
            }
        }
        return .badStatus(0)
    }
}

/// 同步服务依赖的 WebDAV 能力抽象（便于测试替身）。
protocol WebDAVServicing {
    func download(path: String) async throws -> Data?   // 远端不存在返回 nil
    func upload(path: String, data: Data) async throws
    func testConnection() async throws
}

/// P4.1 最小 WebDAV 客户端：PROPFIND / GET / PUT / DELETE / MKCOL。
/// 复用 `NetworkService` 的重试退避、并发上限与本地日志；Basic 鉴权按请求注入。
struct WebDAVClient {
    let config: WebDAVConfig
    private let password: String
    private let network: NetworkService

    init(config: WebDAVConfig, password: String, network: NetworkService = NetworkService()) {
        self.config = config
        self.password = password
        self.network = network
    }

    // MARK: 内部

    private func authHeaders() -> [String: String] {
        let token = Data("\(config.username):\(password)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(token)"]
    }

    /// 拼接远端 URL：`baseURL/[directory/]path`。
    func url(for path: String) -> URL? {
        var base = config.baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        var comps = [base]
        let dir = config.directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !dir.isEmpty { comps.append(dir) }
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !clean.isEmpty { comps.append(clean) }
        return URL(string: comps.joined(separator: "/"))
    }

    private func perform(_ request: Request) async throws -> Data {
        do {
            let (data, _) = try await network.data(for: request)
            return data
        } catch {
            throw WebDAVError.map(error)
        }
    }

    // MARK: 操作

    /// PROPFIND Depth:1，返回目录/文件列表。
    func list(_ path: String = "") async throws -> [WebDAVItem] {
        guard let url = url(for: path) else { throw WebDAVError.invalidURL }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getcontentlength/><D:getlastmodified/></D:prop></D:propfind>
        """
        var headers = authHeaders()
        headers["Depth"] = "1"
        headers["Content-Type"] = "application/xml; charset=utf-8"
        let data = try await perform(Request(url: url, method: .propfind, headers: headers, body: Data(body.utf8)))
        return WebDAVMultistatusParser.parse(data)
    }

    func get(_ path: String) async throws -> Data {
        guard let url = url(for: path) else { throw WebDAVError.invalidURL }
        return try await perform(Request(url: url, method: .get, headers: authHeaders()))
    }

    func put(_ path: String, data: Data) async throws {
        guard let url = url(for: path) else { throw WebDAVError.invalidURL }
        var headers = authHeaders()
        headers["Content-Type"] = "application/octet-stream"
        _ = try await perform(Request(url: url, method: .put, headers: headers, body: data))
    }

    func delete(_ path: String) async throws {
        guard let url = url(for: path) else { throw WebDAVError.invalidURL }
        _ = try await perform(Request(url: url, method: .delete, headers: authHeaders()))
    }

    func makeCollection(_ path: String = "") async throws {
        guard let url = url(for: path) else { throw WebDAVError.invalidURL }
        _ = try await perform(Request(url: url, method: .mkcol, headers: authHeaders()))
    }

    /// 测试连接：列目录成功即通过；目录不存在（404）则尝试创建；鉴权失败（401/403）抛错。
    func testConnection() async throws {
        do {
            _ = try await list("")
        } catch WebDAVError.notFound {
            try await makeCollection("")
        }
    }
}

extension WebDAVClient: WebDAVServicing {
    func download(path: String) async throws -> Data? {
        do { return try await get(path) }
        catch WebDAVError.notFound { return nil }
    }

    func upload(path: String, data: Data) async throws {
        try await put(path, data: data)
    }
}

// MARK: - P4.1 PROPFIND 207 Multi-Status 解析

/// 使用 `XMLParser`（打开命名空间处理）宽容解析 DAV multistatus，
/// 适配 `D:` / `d:` / 无前缀等多种命名空间写法。
final class WebDAVMultistatusParser: NSObject, XMLParserDelegate {
    private struct Partial {
        var href = ""
        var isDirectory = false
        var contentLength: Int?
        var lastModified: Date?
    }

    private var items: [WebDAVItem] = []
    private var current: Partial?
    private var buffer = ""

    static func parse(_ data: Data) -> [WebDAVItem] {
        let delegate = WebDAVMultistatusParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        buffer = ""
        switch elementName {
        case "response": current = Partial()
        case "collection": current?.isDirectory = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer { buffer = "" }
        guard var cur = current else { return }
        switch elementName {
        case "href":
            cur.href = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            current = cur
        case "getcontentlength":
            cur.contentLength = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
            current = cur
        case "getlastmodified":
            cur.lastModified = Self.parseHTTPDate(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
            current = cur
        case "response":
            if !cur.href.isEmpty {
                items.append(WebDAVItem(href: cur.href, isDirectory: cur.isDirectory,
                                        contentLength: cur.contentLength, lastModified: cur.lastModified))
            }
            current = nil
        default: break
        }
    }

    private static func parseHTTPDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: s)
    }
}
