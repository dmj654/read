import SwiftUI
import UIKit

// MARK: - P5.1 自适应布局

/// 布局模式：紧凑宽度用 TabView；常规宽度（iPad / 大窗）用分栏。
enum LayoutMode: String, CaseIterable, Hashable, Sendable {
    case tabs
    case split
}

/// 纯逻辑：按「是否紧凑宽度」判定布局模式（便于单测，不依赖 UIKit）。
enum LayoutResolver {
    static func mode(horizontalCompact: Bool) -> LayoutMode {
        horizontalCompact ? .tabs : .split
    }
}

// MARK: - P5.2 Reduce Motion 动画策略

/// 尊重「减弱动态效果」：开启时禁用过渡动画，仅保留淡入淡出。
enum ReaderMotionPolicy {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .slide
    }
}

// MARK: - P5.2 无障碍标签（统一生成，纯字符串便于测试）

enum A11yLabels {
    static func book(_ title: String, type: ContentType, progress: Double) -> String {
        "《\(title)》，\(type == .comic ? "漫画" : "小说")，已读 \(percent(progress))"
    }

    static func download(_ fileName: String, state: DownloadState, progress: Double) -> String {
        "\(fileName)，\(downloadState(state))，\(percent(progress))"
    }

    static func downloadState(_ state: DownloadState) -> String {
        switch state {
        case .queued: return "排队中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "下载失败"
        }
    }

    static func searchResult(_ title: String, author: String?) -> String {
        if let author, !author.isEmpty { return "\(title)，作者 \(author)" }
        return title
    }

    static func percent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }
}

// MARK: - P5 设计令牌（8pt 网格 + 语义色，避免硬编码）

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

/// 语义化颜色：跟随系统外观（Dark Mode）与强调色，不硬编码具体色值。
enum Palette {
    static var accent: Color { .accentColor }
    static var primaryText: Color { .primary }
    static var secondaryText: Color { .secondary }
    static var success: Color { .green }
    static var warning: Color { .orange }
    static var danger: Color { .red }
    static var surface: Color { Color(UIColor.secondarySystemBackground) }
}
