import XCTest
import SwiftUI
@testable import ReadingApp

// MARK: - P5 iPad 适配 / 无障碍 单元测试
//
// 全部基于纯逻辑类型（`LayoutResolver` / `ReaderMotionPolicy` / `A11yLabels` / `AppSection`），
// 不依赖 UIKit 渲染、不发起任何网络请求，可在任意模拟器上秒级跑完。

final class P5Tests: XCTestCase {

    // MARK: - P5.1 自适应布局判定

    func testCompactWidthResolvesToTabs() {
        XCTAssertEqual(LayoutResolver.mode(horizontalCompact: true), .tabs)
    }

    func testRegularWidthResolvesToSplit() {
        XCTAssertEqual(LayoutResolver.mode(horizontalCompact: false), .split)
    }

    /// 布局模式集合必须闭合：只允许 tabs / split 两种，避免新增 case 后根视图漏处理。
    func testLayoutModeCasesAreClosed() {
        XCTAssertEqual(LayoutMode.allCases, [.tabs, .split])
    }

    /// iPhone 竖屏（compact）与 iPad（regular）判定的对称性：同一入参必须稳定返回同一结果。
    func testLayoutResolverIsDeterministic() {
        for _ in 0..<20 {
            XCTAssertEqual(LayoutResolver.mode(horizontalCompact: true), .tabs)
            XCTAssertEqual(LayoutResolver.mode(horizontalCompact: false), .split)
        }
    }

    // MARK: - P5.1 顶层分区完备性

    func testAppSectionCount() {
        XCTAssertEqual(AppSection.allCases.count, 5)
    }

    /// 侧边栏 / 标签栏都靠这两个字段渲染，任一重复都会导致选中态错乱或图标撞车。
    func testAppSectionTitlesAreUnique() {
        let titles = AppSection.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testAppSectionSystemImagesAreUniqueAndNonEmpty() {
        let icons = AppSection.allCases.map(\.systemImage)
        XCTAssertEqual(Set(icons).count, icons.count)
        XCTAssertFalse(icons.contains(where: \.isEmpty))
    }

    func testAppSectionIdentifiersMatchRawValues() {
        for section in AppSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
        }
    }

    // MARK: - P5.2 减弱动态效果

    /// 开启「减弱动态效果」时不得有过渡动画（nil 表示禁用）。
    func testReduceMotionDisablesAnimation() {
        XCTAssertNil(ReaderMotionPolicy.animation(reduceMotion: true))
    }

    /// 常规状态下保留 0.2s 缓动，保证翻页有可感知的连续感。
    func testNormalMotionKeepsAnimation() {
        XCTAssertNotNil(ReaderMotionPolicy.animation(reduceMotion: false))
    }

    // MARK: - P5.2 书架朗读标签

    func testBookLabelForNovel() {
        let label = A11yLabels.book("三体", type: .novel, progress: 0.42)
        XCTAssertTrue(label.contains("三体"))
        XCTAssertTrue(label.contains("小说"))
        XCTAssertTrue(label.contains("42%"))
        XCTAssertFalse(label.contains("漫画"))
    }

    func testBookLabelForComic() {
        let label = A11yLabels.book("海贼王", type: .comic, progress: 1.0)
        XCTAssertTrue(label.contains("漫画"))
        XCTAssertTrue(label.contains("100%"))
    }

    /// 进度越界（负值 / 超过 1）必须被夹紧，避免 VoiceOver 读出 -20% 或 130%。
    func testBookLabelClampsOutOfRangeProgress() {
        XCTAssertTrue(A11yLabels.book("A", type: .novel, progress: -0.5).contains("0%"))
        XCTAssertTrue(A11yLabels.book("A", type: .novel, progress: 1.7).contains("100%"))
    }

    // MARK: - P5.2 下载状态朗读

    func testDownloadStateLabelsForAllStates() {
        let expected: [DownloadState: String] = [
            .queued: "排队中",
            .downloading: "下载中",
            .paused: "已暂停",
            .completed: "已完成",
            .failed: "下载失败"
        ]
        for (state, text) in expected {
            XCTAssertEqual(A11yLabels.downloadState(state), text, "状态 \(state.rawValue) 文案不匹配")
        }
    }

    func testDownloadLabelCombinesNameStateAndProgress() {
        let label = A11yLabels.download("第一章.xhtml", state: .downloading, progress: 0.25)
        XCTAssertTrue(label.contains("第一章.xhtml"))
        XCTAssertTrue(label.contains("下载中"))
        XCTAssertTrue(label.contains("25%"))
    }

    // MARK: - P5.2 搜索结果朗读

    func testSearchResultLabelWithAuthor() {
        XCTAssertEqual(A11yLabels.searchResult("三体", author: "刘慈欣"), "三体，作者 刘慈欣")
    }

    func testSearchResultLabelWithoutAuthor() {
        XCTAssertEqual(A11yLabels.searchResult("三体", author: nil), "三体")
    }

    /// 空字符串作者视为缺失，避免读成「作者 」这种残缺句子。
    func testSearchResultLabelWithBlankAuthor() {
        XCTAssertEqual(A11yLabels.searchResult("三体", author: ""), "三体")
    }

    // MARK: - P5.2 百分比格式化

    func testPercentRoundsToNearestInteger() {
        XCTAssertEqual(A11yLabels.percent(0.004), "0%")
        XCTAssertEqual(A11yLabels.percent(0.005), "1%")
        XCTAssertEqual(A11yLabels.percent(0.335), "34%")
        XCTAssertEqual(A11yLabels.percent(0.999), "100%")
    }

    func testPercentClampsBounds() {
        XCTAssertEqual(A11yLabels.percent(-3), "0%")
        XCTAssertEqual(A11yLabels.percent(9), "100%")
    }
}
