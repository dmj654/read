import Foundation

enum SourceImporterError: Error, Equatable {
    case invalidJSON
}

/// P0.19 书源 JSON 导入解析：Legado 书源 JSON → `SourceRule`。
///
/// 字段映射：
/// - `bookSourceName` → name
/// - `bookSourceUrl` → 缺 searchUrl 时兜底为搜索地址
/// - `bookSourceType`：3 = 漫画，其余（含缺失）→ 小说
/// - `enabled`：缺失默认 true
/// - `ruleSearch/ruleBookInfo/ruleToc/ruleContent`：可为 String 或 Object（Object 序列化为 JSON 字符串）
enum SourceImporter {
    static func `import`(json: Data) throws -> SourceRule {
        // JSONSerialization 自身会抛 NSCocoaError，对外统一收敛为 invalidJSON，
        // 便于调用方只处理一种错误类型。
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: json)
        } catch {
            throw SourceImporterError.invalidJSON
        }
        guard let obj = raw as? [String: Any] else {
            throw SourceImporterError.invalidJSON
        }

        let name = (obj["bookSourceName"] as? String) ?? ""
        let sourceUrl = obj["bookSourceUrl"] as? String
        let typeInt = obj["bookSourceType"] as? Int
        let type: ContentType = (typeInt == 3) ? .comic : .novel
        let enabled = (obj["enabled"] as? Bool) ?? true

        let ruleSearchDict = obj["ruleSearch"] as? [String: Any]
        let searchUrl = (ruleSearchDict?["searchUrl"] as? String) ?? (sourceUrl ?? "")
        let ruleSearch = stringify(ruleSearchDict)
        let ruleBookInfo = stringify(obj["ruleBookInfo"])
        let ruleToc = stringify(obj["ruleToc"])
        let ruleContent = stringify(obj["ruleContent"])

        return SourceRule(
            name: name,
            type: type,
            enabled: enabled,
            priority: 0,
            searchUrl: searchUrl,
            ruleSearch: ruleSearch ?? "",
            ruleBookInfo: ruleBookInfo ?? "",
            ruleToc: ruleToc ?? "",
            ruleContent: ruleContent ?? ""
        )
    }

    /// 兼容 Legado 中规则字段可能为 String 或 Object 的写法：Object 序列化为 JSON 字符串。
    private static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict) {
            return String(data: data, encoding: .utf8)
        }
        if let arr = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: arr) {
            return String(data: data, encoding: .utf8)
        }
        return "\(value)"
    }
}
