import Foundation

/// P0.21 夹具加载助手：从测试源码目录下的 `Fixtures/` 读取资产。
///
/// 采用 `#file` 相对路径方案，夹具文件无需加入 test target 的 Copy Bundle Resources，
/// 也不依赖运行时工作目录，路径稳定、CI/本地一致。
enum FixtureSupport {
    static func loadFixture(_ name: String) -> Data? {
        let dir = URL(fileURLWithPath: #file).deletingLastPathComponent()
        let url = dir.appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }

    static func loadFixtureString(_ name: String) -> String? {
        loadFixture(name).flatMap { String(data: $0, encoding: .utf8) }
    }
}
