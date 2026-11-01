import Foundation

/// P2.4 落盘抽象：下载完成的临时文件移动到稳定目录（按 fileName 隔离）。
/// 生产环境指向 applicationSupport/Library/Books；测试可注入临时目录。
protocol FileStoring: Sendable {
    var baseDirectory: URL { get }
    func destinationURL(for fileName: String) -> URL
    func persist(from tempURL: URL, fileName: String) throws -> URL
    func exists(fileName: String) -> Bool
    func sizeOfDirectory() throws -> Int64
}

struct DownloadFileManager: FileStoring {
    let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func destinationURL(for fileName: String) -> URL {
        baseDirectory.appendingPathComponent(Self.safeFileName(fileName))
    }

    /// 将系统交付的临时文件移动到最终落盘位置（覆盖同名）。
    func persist(from tempURL: URL, fileName: String) throws -> URL {
        let dest = destinationURL(for: fileName)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: destinationURL(for: fileName).path)
    }

    func sizeOfDirectory() throws -> Int64 {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey])
        return try urls.reduce(0) { acc, url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return acc + Int64(values.fileSize ?? 0)
        }
    }

    /// 安全文件名：剔除路径分隔符与文件系统非法字符，空白同样替换为下划线，
    /// 连续下划线折叠为一个；全空时降级为 UUID。
    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.whitespacesAndNewlines)
        var cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        while cleaned.contains("__") {
            cleaned = cleaned.replacingOccurrences(of: "__", with: "_")
        }
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

    /// 生产落盘根目录（应用支持目录下的 Library/Books）。
    static let production: DownloadFileManager = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Library/Books", isDirectory: true)
        return DownloadFileManager(baseDirectory: base)
    }()
}
