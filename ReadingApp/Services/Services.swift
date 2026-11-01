import Foundation
import Logging

// MARK: - 网络层（P0-C）

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    // P4 WebDAV 扩展
    case put = "PUT"
    case delete = "DELETE"
    case propfind = "PROPFIND"
    case mkcol = "MKCOL"
}

enum NetworkError: Error, Equatable {
    case badStatus(Int)
    case noData
    case transport(Error)
}

/// 统一请求描述。
struct Request: Sendable {
    var url: URL
    var method: HTTPMethod = .get
    var headers: [String: String] = [:]
    var body: Data? = nil
    var timeout: TimeInterval = 30
}

/// URLSession 抽象，便于测试注入桩实现（P0.7 可测性基石）。
protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// 本地 Cookie 罐：按域名存取，请求前注入、响应后吸收（P0.8）。
final class CookieJar: @unchecked Sendable {
    private var store: [String: [HTTPCookie]] = [:]
    private let lock = NSLock()

    func setCookies(_ cookies: [HTTPCookie], for url: URL) {
        guard let host = url.host else { return }
        lock.lock()
        var list = store[host] ?? []
        for c in cookies {
            if let idx = list.firstIndex(where: { $0.name == c.name }) { list[idx] = c }
            else { list.append(c) }
        }
        store[host] = list
        lock.unlock()
    }

    func attach(to request: inout URLRequest) {
        guard let url = request.url, let host = url.host else { return }
        lock.lock(); let list = store[host] ?? []; lock.unlock()
        for (k, v) in HTTPCookie.requestHeaderFields(with: list) {
            request.setValue(v, forHTTPHeaderField: k)
        }
    }

    func absorb(from response: HTTPURLResponse, for url: URL) {
        if let fields = response.allHeaderFields as? [String: String],
           let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            setCookies(cookies, for: url)
        }
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        guard let host = url.host else { return [] }
        lock.lock(); let list = store[host] ?? []; lock.unlock()
        return list
    }
}

/// 本地请求日志处理器：默认关闭，仅记录 method/url/status，绝不外发（P0.11）。
final class CollectingLogHandler: LogHandler, @unchecked Sendable {
    var enabled = false
    private var _entries: [String] = []
    private let lock = NSLock()
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider? = nil

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        guard enabled else { return }
        lock.lock(); _entries.append("\(level): \(message)"); lock.unlock()
    }
    func entries() -> [String] { lock.lock(); defer { lock.unlock() }; return _entries }
    func clear() { lock.lock(); _entries.removeAll(); lock.unlock() }
}

/// 网络日志门面（swift-log 驱动，生产环境受开关控制）。
struct NetworkLogger {
    static let shared = NetworkLogger()
    static private var didBootstrap = false
    private let handler = CollectingLogHandler()

    private init() {
        if !Self.didBootstrap {
            Self.didBootstrap = true
            LoggingSystem.bootstrap { [handler] _ in handler }
        }
    }

    var enabled: Bool { handler.enabled }
    func setEnabled(_ on: Bool) { handler.enabled = on }
    func clear() { handler.clear() }
    func entries() -> [String] { handler.entries() }

    private var logger: Logger { Logger(label: "com.example.ReadingApp.network") }

    func log(request: Request, status: Int?) {
        guard enabled else { return }
        let tail = status.map { " -> \($0)" } ?? ""
        logger.info("\(request.method.rawValue) \(request.url.absoluteString)\(tail)")
    }
}

/// 后台会话工厂（P0.12 / P2.5）：预留给 DownloadManager 的 background 配置。
enum NetworkSessionFactory {
    /// 后台下载会话配置：区别于前台 `NetworkService`，允许进程退到后台后继续传输。
    static func backgroundConfig(forIdentifier id: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return config
    }

    static func background(forIdentifier id: String) -> URLSession {
        URLSession(configuration: backgroundConfig(forIdentifier: id))
    }
}

/// 统一网络服务：异步封装 + Cookie + 重试退避 + 并发上限 + 本地日志（P0.7–P0.11）。
final class NetworkService: @unchecked Sendable {
    private let session: URLSessionProtocol
    private let cookieJar: CookieJar
    private let logger: NetworkLogger
    private let maxConcurrency: Int
    private let maxRetry: Int
    private let semaphore: DispatchSemaphore

    init(session: URLSessionProtocol = URLSession.shared,
         cookieJar: CookieJar = CookieJar(),
         logger: NetworkLogger = .shared,
         maxConcurrency: Int = 6,
         maxRetry: Int = 2) {
        self.session = session
        self.cookieJar = cookieJar
        self.logger = logger
        self.maxConcurrency = maxConcurrency
        self.maxRetry = maxRetry
        self.semaphore = DispatchSemaphore(value: maxConcurrency)
    }

    func data(for request: Request) async throws -> (Data, HTTPURLResponse) {
        return try await withRetry(maxRetry) {
            self.semaphore.wait()
            defer { self.semaphore.signal() }
            let urlRequest = self.buildURLRequest(from: request)
            let (data, response) = try await self.session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.badStatus(0)
            }
            self.cookieJar.absorb(from: http, for: request.url)
            self.logger.log(request: request, status: http.statusCode)
            guard (200..<300).contains(http.statusCode) else {
                throw NetworkError.badStatus(http.statusCode)
            }
            return (data, http)
        }
    }

    private func buildURLRequest(from request: Request) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method.rawValue
        for (k, v) in request.headers { urlRequest.setValue(v, forHTTPHeaderField: k) }
        if let body = request.body { urlRequest.httpBody = body }
        cookieJar.attach(to: &urlRequest)
        return urlRequest
    }

    private func withRetry(_ max: Int, _ op: () async throws -> (Data, HTTPURLResponse)) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do { return try await op() }
            catch {
                let retryable: Bool
                if case NetworkError.badStatus(let code) = error {
                    retryable = (500..<600).contains(code)
                } else {
                    retryable = true
                }
                attempt += 1
                if !retryable || attempt > max { throw error }
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 50_000_000))
            }
        }
    }
}
