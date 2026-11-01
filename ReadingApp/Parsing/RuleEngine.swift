import Foundation
import Kanna
import JavaScriptCore

// MARK: - 解析引擎（P0-D：同源规则核心）

enum RuleEngineError: Error, Equatable {
    case invalidRegex(String)
    case jsError(String)
    case emptyInput
}

/// 算子：由分词器从 Legado 风格规则串解析而来。
enum ROperator: Equatable {
    case xpath(String)
    case css(String)
    case regex(pattern: String, flags: String)
    case replace(pattern: String, replacement: String)
    case js(String)
    case literal(String)
}

// MARK: - P0.13 规则算子分词器

/// 将规则串解析为算子序列。规则串可链式组合，例如 `//h1@js:result.trim()`。
/// 算子识别顺序（与 Legado 一致）：`@js:` → `##` 替换 → `//` XPath → `css>` CSS → `/.../flags` 正则 → 纯文本。
enum RuleTokenizer {
    static func tokenize(_ rule: String) -> [ROperator] {
        var ops: [ROperator] = []
        var remaining = Substring(rule)

        while !remaining.isEmpty {
            if remaining.hasPrefix("@js:") {
                let code = String(remaining.dropFirst(4))
                ops.append(.js(code))
                remaining = ""
            } else if let rng = remaining.range(of: "##") {
                let head = String(remaining[..<rng.lowerBound])
                let tail = String(remaining[rng.upperBound...])
                ops.append(.replace(pattern: head, replacement: tail))
                remaining = ""
            } else if remaining.hasPrefix("//") {
                let end = nextDelimiter(in: remaining, after: 2)
                let expr = String(remaining[remaining.startIndex..<end])
                ops.append(.xpath(expr))
                remaining = remaining[end...]
            } else if remaining.hasPrefix("css>") {
                let start = remaining.index(remaining.startIndex, offsetBy: 4)
                let end = nextDelimiter(in: remaining, after: 4)
                let expr = String(remaining[start..<end])
                ops.append(.css(expr))
                remaining = remaining[end...]
            } else if remaining.hasPrefix("/") {
                if let (pattern, flags, end) = parseSlashRegex(remaining) {
                    ops.append(.regex(pattern: pattern, flags: flags))
                    remaining = remaining[end...]
                } else {
                    ops.append(.literal(String(remaining)))
                    remaining = ""
                }
            } else {
                let end = nextDelimiter(in: remaining, after: 0)
                let text = String(remaining[..<end])
                ops.append(.literal(text))
                remaining = remaining[end...]
            }
        }
        return ops
    }

    /// 找到下一个算子分隔符（`@js:` 或 `##`）的位置，否则返回末尾。
    private static func nextDelimiter(in s: Substring, after offset: Int) -> Substring.Index {
        let start = s.index(s.startIndex, offsetBy: min(offset, s.count))
        var i = start
        while i < s.endIndex {
            let tail = s[i...]
            if tail.hasPrefix("@js:") || tail.hasPrefix("##") { return i }
            i = s.index(after: i)
        }
        return s.endIndex
    }

    /// 解析 `/pattern/flags` 形式（pattern 内不含未转义 `/`，P0 约定）。
    private static func parseSlashRegex(_ s: Substring) -> (pattern: String, flags: String, end: Substring.Index)? {
        var i = s.index(after: s.startIndex)
        var pattern = ""
        while i < s.endIndex {
            let ch = s[i]
            if ch == "/" {
                let flags = String(s[s.index(after: i)...])
                return (pattern, flags, s.endIndex)
            }
            pattern.append(ch)
            i = s.index(after: i)
        }
        return nil
    }
}

// MARK: - P0.14 / P0.15 / P0.16 / P0.17 求值器 + 统一入口

/// 同源规则回放引擎：在 source（通常是 HTML）上链式执行算子，返回所有匹配文本。
enum RuleEngine {
    static func evaluate(_ rule: String, source: String) -> [String] {
        let ops = RuleTokenizer.tokenize(rule)
        var current: [String] = [source]
        for op in ops { current = apply(op, to: current) }
        return current
    }

    /// 返回首个非空匹配（复合规则取单值用）。
    static func first(_ rule: String, source: String) -> String? {
        evaluate(rule, source: source).first { !$0.isEmpty }
    }

    /// 多值以分隔符拼接（正文/目录常用）。
    static func joined(_ rule: String, source: String, separator: String = "\n") -> String {
        evaluate(rule, source: source).joined(separator: separator)
    }

    /// P3 扩展：返回 xpath/css 命中节点的**外部 HTML**（用于漫画「先取图片容器、再逐容器抽图」）。
    /// 非 xpath/css 算子退化为 `evaluate` 文本求值；空规则返回整段 source（视为单一容器）。
    static func evaluateElements(_ rule: String, source: String) -> [String] {
        let ops = RuleTokenizer.tokenize(rule)
        var current: [String] = [source]
        for op in ops { current = applyElements(op, to: current) }
        return current
    }

    private static func applyElements(_ op: ROperator, to inputs: [String]) -> [String] {
        switch op {
        case .xpath(let expr):
            return inputs.flatMap { html -> [String] in
                guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
                return doc.xpath(expr).compactMap { $0.toHTML }
            }
        case .css(let expr):
            return inputs.flatMap { html -> [String] in
                guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
                return doc.css(expr).compactMap { $0.toHTML }
            }
        default:
            return apply(op, to: inputs)
        }
    }

    /// P1 扩展：识别 `...@attr` 后缀（仅当 `@` 位于表达式末尾、且前段非空），用于抽取节点属性（如 `//a@href`）。
    private static func splitAttribute(_ expr: String) -> (base: String, attr: String)? {
        guard let range = expr.range(of: "@(\\w+)$", options: .regularExpression) else { return nil }
        let attr = String(expr[range].dropFirst())
        let base = String(expr[..<range.lowerBound])
        return base.isEmpty ? nil : (base, attr)
    }

    private static func apply(_ op: ROperator, to inputs: [String]) -> [String] {
        switch op {
        case .xpath(let expr):
            if let (base, attr) = splitAttribute(expr) {
                return inputs.flatMap { html -> [String] in
                    guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
                    return doc.xpath(base).compactMap { $0[attr] }
                }
            }
            return inputs.flatMap { html -> [String] in
                guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
                return doc.xpath(expr).compactMap { $0.text }
            }
        case .css(let expr):
            if let (base, attr) = splitAttribute(expr) {
                return inputs.flatMap { html -> [String] in
                    guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
                    return doc.css(base).compactMap { $0[attr] }
                }
            }
            return inputs.flatMap { html -> [String] in
                guard let doc = try? HTML(html: html, encoding: .utf8) else { return [] }
                return doc.css(expr).compactMap { $0.text }
            }
        case .regex(let pattern, let flags):
            return inputs.flatMap { regexMatch(pattern, flags: flags, in: $0) }
        case .replace(let pattern, let replacement):
            return inputs.map { regexReplace(pattern, replacement: replacement, in: $0) }
        case .js(let code):
            return inputs.compactMap { runJS(code, result: $0) }
        case .literal(let t):
            return inputs.map { _ in t }
        }
    }

    // P0.14 正则
    private static func regexOptions(_ flags: String) -> NSRegularExpression.Options {
        var opts: NSRegularExpression.Options = []
        if flags.contains("i") { opts.insert(.caseInsensitive) }
        if flags.contains("m") { opts.insert(.anchorsMatchLines) }
        if flags.contains("s") { opts.insert(.dotMatchesLineSeparators) }
        return opts
    }

    private static func regexMatch(_ pattern: String, flags: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: regexOptions(flags)) else { return [] }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.map { m in
            let range = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
            return ns.substring(with: range)
        }
    }

    private static func regexReplace(_ pattern: String, replacement: String, in text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let ns = text as NSString
        return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: replacement)
    }

    // P0.17 JS 注入（JavaScriptCore 沙箱，无 DOM / 网络）
    private static func runJS(_ code: String, result: String) -> String? {
        guard let context = JSContext(virtualMachine: nil) else { return nil }
        context.setObject(result, forKeyedSubscript: "result" as NSString)
        context.setObject(NSObject(), forKeyedSubscript: "java" as NSString) // 最小桩，无实际方法
        guard let value = context.evaluateScript(code) else {
            return nil // JS 抛错：不崩溃，返回 nil
        }
        if value.isUndefined || value.isNull { return nil }
        if let arr = value.toArray() { return arr.map { "\($0)" }.joined(separator: "\n") }
        return value.toString()
    }
}

// MARK: - P0.18 复合规则拼装

/// 书详情结构化结果（由 ruleBookInfo 多字段规则组装）。
struct BookInfo {
    var title: String?
    var author: String?
    var intro: String?
    var coverURL: String?
    var status: String?
    var category: String?
}

/// 解析 Legado `ruleBookInfo` 多字段结构：`field: rule` 每行一条，支持书名/作者/简介/封面/状态/分类。
enum CompositeRule {
    static func parse(_ source: String, rule: String) -> BookInfo {
        var info = BookInfo()
        for line in rule.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let sub = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            assign(&info, key: key, value: RuleEngine.first(sub, source: source))
        }
        return info
    }

    private static func assign(_ info: inout BookInfo, key: String, value: String?) {
        guard let value, !value.isEmpty else { return }
        switch key {
        case "name", "title", "bookname": info.title = value
        case "author": info.author = value
        case "intro", "description", "summary": info.intro = value
        case "cover", "coverurl", "coverlink": info.coverURL = value
        case "status", "statu", "update": info.status = value
        case "kind", "category", "sort", "class": info.category = value
        default: break
        }
    }
}
